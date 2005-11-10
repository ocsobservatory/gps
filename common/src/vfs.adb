-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2003-2005                       --
--                              AdaCore                              --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

--  This module implements a virtual file system.
--  It gives access to local and remote files, abstract file system specific
--  features (case sensitivity),...

with Ada.Calendar;              use Ada.Calendar;
with Ada.Exceptions;            use Ada.Exceptions;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with System;

with GNAT.Case_Util;            use GNAT.Case_Util;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with GNAT.Heap_Sort;            use GNAT.Heap_Sort;
with GNAT.OS_Lib;               use GNAT.OS_Lib;

with Interfaces.C.Strings;      use Interfaces.C.Strings;

with Glib.Convert;              use Glib.Convert;
with Glib.Unicode;              use Glib.Unicode;
with Glib.Values;               use Glib.Values;

with File_Utils;                use File_Utils;
with OS_Utils;                  use OS_Utils;
with Remote_Connections;        use Remote_Connections;
with String_Utils;              use String_Utils;
with Traces;                    use Traces;

package body VFS is

   Resolve_Links_Handle : constant Debug_Handle :=
      Create ("VFS.Resolve_Links", Off);

   Temporary_Dir : constant String := Get_Tmp_Dir;
   --  Cache the name of the temporary directory

   Empty_String : constant Cst_UTF8_String_Access := new String'("");

   Virtual_File_Type : Glib.GType := Glib.GType_None;
   --  Initialized only the first time this is needed, since we need glib
   --  initialized for this.
   --  ??? Could this be made a local variable

   Working_Dir : GNAT.OS_Lib.String_Access := null;
   --  Working directory. This can be a remote directory

   procedure Ensure_Normalized (File : Virtual_File);
   --  Ensure that the information for the normalized file have been correctly
   --  computed.

   procedure Finalize (Value : in out Contents_Access);
   --  Internal version of Finalize

   function Virtual_File_Boxed_Copy
     (Boxed : System.Address) return System.Address;
   pragma Convention (C, Virtual_File_Boxed_Copy);
   procedure Virtual_File_Boxed_Free (Boxed : System.Address);
   pragma Convention (C, Virtual_File_Boxed_Free);
   --  Subprograms required for the support of GValue

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Contents_Record, Contents_Access);

   pragma Warnings (Off);
   --  This UC is safe aliasing-wise, so kill warning
   function To_Contents_Access is new Ada.Unchecked_Conversion
     (System.Address, Contents_Access);
   pragma Warnings (On);

   ---------
   -- "=" --
   ---------

   function "=" (File1, File2 : Virtual_File) return Boolean is
      Case_Sensitive : Boolean;
   begin
      if File1.Value = null then
         return File2.Value = null;
      elsif File2.Value = null then
         return False;
      elsif File1.Value = File2.Value then
         return True;
      elsif File1.Value.Connection /= File2.Value.Connection then
         return False;
      else
         Ensure_Normalized (File1);
         Ensure_Normalized (File2);
         Case_Sensitive := Filenames_Are_Case_Sensitive
           or File1.Value.Connection /= null;

         return Equal
           (File2.Value.Normalized_Full.all,
            File1.Value.Normalized_Full.all,
            Case_Sensitive);
      end if;
   end "=";

   ------------
   -- Create --
   ------------

   function Create (Full_Filename : UTF8_String) return Virtual_File is
      Protocol, User, Host : String_Access;
      Connection  : Remote_Connection;
      Start       : Integer;
      Valid       : Boolean;
      Invalid_Pos : Natural;
      First       : Natural;
      Last        : Natural;

   begin
      UTF8_Validate (Full_Filename, Valid, Invalid_Pos);
      if not Valid then
         Last := Invalid_Pos - 1;
      else
         Last := Full_Filename'Last;
      end if;
      while Last >= Full_Filename'First loop
         exit when Full_Filename (Last) /= ASCII.LF
           and Full_Filename (Last) /= ASCII.CR;
         Last := Last - 1;
      end loop;
      First := Full_Filename'First;

      Parse_URL (Full_Filename (First .. Last), Protocol, User, Host, Start);

      if Protocol /= null then
         Connection := Get_Connection (Protocol.all, User.all, Host.all);
         Free (Protocol);
         Free (User);
         Free (Host);

         if Connection /= null then
            return
              (Ada.Finalization.Controlled with
               Value => new Contents_Record'
                 (Connection      => Connection,
                  Start_Of_Path   => Start,
                  Ref_Count       => 1,
                  Full_Name       => new String'
                    (Full_Filename (First .. Last)),
                  Normalized_Full => null,
                  Dir_Name        => null,
                  Kind            => Unknown));

         else
            --  Behave as if we have a local file, although nobody will be
            --  able to open it

            return
              (Ada.Finalization.Controlled with
               Value => new Contents_Record'
                 (Connection      => null,
                  Start_Of_Path   => Full_Filename'First,
                  Ref_Count       => 1,
                  Full_Name       => new String'
                    (Full_Filename (First .. Last)),
                  Normalized_Full => null,
                  Dir_Name        => null,
                  Kind            => Unknown));
         end if;

      else
         return
           (Ada.Finalization.Controlled with
            Value => new Contents_Record'
              (Connection      => null,
               Start_Of_Path   => Full_Filename'First,
               Ref_Count       => 1,
               Full_Name       => new String'
                 (Full_Filename (First .. Last)),
               Normalized_Full => null,
               Dir_Name        => null,
               Kind            => Unknown));
      end if;
   end Create;

   ----------------------
   -- Create_From_Base --
   ----------------------

   function Create_From_Base (Base_Name : UTF8_String) return Virtual_File is
   begin
      if Base_Name /= "" then
         return (Ada.Finalization.Controlled with
                 Value => new Contents_Record'
                 (Connection      => null,
                  Start_Of_Path   => Base_Name'First,
                  Ref_Count       => 1,
                  Full_Name       => new String'(Base_Name),
                  Normalized_Full => null,
                  Dir_Name        => null,
                  Kind            => Unknown));
      else
         return No_File;
      end if;
   end Create_From_Base;

   -----------------------
   -- Ensure_Normalized --
   -----------------------

   procedure Ensure_Normalized (File : Virtual_File) is
   begin
      if File.Value.Normalized_Full = null then
         --  If the user didn't create a file with a full name, no need to
         --  spend time now trying to find the file.

         if File.Value.Connection = null and then
           not Is_Absolute_Path (File.Value.Full_Name.all) then
            File.Value.Normalized_Full :=
              new UTF8_String'(File.Value.Full_Name.all);

         elsif File.Value.Connection /= null then
            --  Simplified normalization
            --  ../ and ./ directories handling

            declare
               --  Normalized path cannot be greater than initial one.
               Normalized : UTF8_String (1 .. File.Value.Full_Name'Length);
               Norm_Index : Natural := 1;
               Start, Last : Natural;

            begin
               --  first copy header (i.e. protocol://host/)
               Last := File.Value.Start_Of_Path;
               Start := File.Value.Full_Name'First;
               Norm_Index := Last - Start + 1;
               Normalized (1 .. Norm_Index) :=
                 File.Value.Full_Name (Start .. Last);
               Start := Last + 1;
               Last  := Start;

               while Last <= File.Value.Full_Name'Last loop
                  if File.Value.Full_Name (Last) = '/' then
                     if File.Value.Full_Name (Start .. Last) = "./" then
                        --  just ignore it
                        Start := Last + 1;

                     elsif File.Value.Full_Name (Start .. Last) = "../" then
                        --  remove previous directory
                        Norm_Index := Norm_Index - 1;

                        while Normalized (Norm_Index) /= '/' loop
                           Norm_Index := Norm_Index - 1;
                           exit when Norm_Index = 1;
                        end loop;
                        --  and ignore '..'
                        Start := Last + 1;

                     else
                        --  new directory. Add it to normalized.
                        Norm_Index := Norm_Index + 1;
                        Normalized (Norm_Index ..
                                      Norm_Index + Last - Start) :=
                            File.Value.Full_Name (Start .. Last);
                        Norm_Index := Norm_Index + Last - Start;
                        Start := Last + 1;
                     end if;

                  elsif Last = File.Value.Full_Name'Last then
                     Norm_Index := Norm_Index + 1;
                     Normalized (Norm_Index .. Norm_Index + Last - Start) :=
                       File.Value.Full_Name (Start .. Last);
                     Norm_Index := Norm_Index + Last - Start;
                  end if;

                  Last := Last + 1;
               end loop;

               File.Value.Normalized_Full := new UTF8_String'
                 (Normalized (1 .. Norm_Index));
            end;

         else
            --  To_Host_Pathname is only needed for the debugger: it is done
            --     in Open_File_Editor.
            --  Normalize_Pathname with link resolution is not needed, since
            --     we want to keep links anyway (they have been checked for
            --     the application's source files, and do not matter for other
            --     files on the system).
            --  Conversion to and from UTF8 are not needed, since '.' and '/'
            --     are encoded the same in UTF8 anyway.

            if File.Value.Full_Name (File.Value.Full_Name'Last) = '/' or else
              File.Value.Full_Name (File.Value.Full_Name'Last) = '\' then
               declare
                  Normalized : constant String := Normalize_Pathname
                    (File.Value.Full_Name.all,
                     Resolve_Links => Active (Resolve_Links_Handle));
               begin
                  if Normalized (Normalized'Last) /= Dir_Separator then
                     File.Value.Normalized_Full := new UTF8_String'
                       (Normalized & Dir_Separator);
                  else
                     File.Value.Normalized_Full := new UTF8_String'
                       (Normalized);
                  end if;
               end;

            else
               File.Value.Normalized_Full := new UTF8_String'
                 (Normalize_Pathname
                    (File.Value.Full_Name.all,
                     Resolve_Links => Active (Resolve_Links_Handle)));
            end if;

            if not File_Utils.Filenames_Are_Case_Sensitive then
               To_Lower (File.Value.Normalized_Full.all);
            end if;
         end if;
      end if;
   end Ensure_Normalized;

   ---------------
   -- Base_Name --
   ---------------

   function Base_Name
     (File : Virtual_File; Suffix : String := "") return Glib.UTF8_String is
   begin
      if File.Value = null
        or else File.Value.Full_Name = null
        or else File.Value.Full_Name.all = ""
      then
         return "";
      end if;

      if File.Value.Full_Name (File.Value.Full_Name'Last) = '/' or
        File.Value.Full_Name (File.Value.Full_Name'Last) = '\' then

         return "";
      end if;

      --  Since we can't ensure that Prefix will be the same in two
      --  successive calls, we have to reallocate the string every time.

      return Base_Name
        (File.Value.Full_Name
           (File.Value.Start_Of_Path .. File.Value.Full_Name'Last), Suffix);
   end Base_Name;

   -------------------
   -- Base_Dir_Name --
   -------------------

   function Base_Dir_Name
     (File : Virtual_File) return Glib.UTF8_String is
   begin
      if File.Value = null
        or else File.Value.Full_Name = null
        or else File.Value.Full_Name.all = ""
      then
         return "";
      end if;

      if File.Value.Full_Name (File.Value.Full_Name'Last) = '/' or
        File.Value.Full_Name (File.Value.Full_Name'Last) = '\' then
         return Base_Name
           (File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last - 1));
      else
         return Base_Name
           (File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
      end if;
   end Base_Dir_Name;

   ---------------
   -- Full_Name --
   ---------------

   function Full_Name
     (File : Virtual_File; Normalize : Boolean := False)
      return Cst_UTF8_String_Access is
   begin
      if File.Value = null then
         return Empty_String;

      elsif Normalize then
         Ensure_Normalized (File);
         return Cst_UTF8_String_Access (File.Value.Normalized_Full);

      elsif File.Value.Connection /= null then
         return Cst_UTF8_String_Access (File.Value.Full_Name);
      else
         return Cst_UTF8_String_Access (File.Value.Full_Name);
      end if;
   end Full_Name;

   ---------------
   -- Host_Name --
   ---------------

   function Get_Host (File : Virtual_File) return UTF8_String is
   begin
      if File.Value = null then
         return "";
      else
         if File.Value.Connection /= null then
            return Get_Host (File.Value.Connection);
         else
            return "";
         end if;
      end if;
   end Get_Host;

   --------------
   -- Dir_Name --
   --------------

   function Dir_Name (File : Virtual_File) return Cst_UTF8_String_Access is
   begin
      if File.Value = null then
         return Empty_String;
      else
         if File.Value.Dir_Name = null then
            File.Value.Dir_Name :=
              new UTF8_String'(Dir_Name (File.Value.Full_Name.all));
         end if;
         return Cst_UTF8_String_Access (File.Value.Dir_Name);
      end if;
   end Dir_Name;

   ---------
   -- Dir --
   ---------

   function Dir (File : Virtual_File) return Virtual_File is
      The_Dir      : Virtual_File;
      The_Dir_Name : constant String := Dir_Name (File).all;
   begin
      if The_Dir_Name = "" then
         return VFS.No_File;
      else
         The_Dir := Create (The_Dir_Name);
         The_Dir.Value.Kind := Directory;
         return The_Dir;
      end if;
   end Dir;

   ------------
   -- Delete --
   ------------

   procedure Delete
     (File    : Virtual_File;
      Success : out Boolean) is
   begin
      if File.Value.Connection = null then
         Delete_File (Locale_Full_Name (File), Success);
      else
         Success := Delete
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
      end if;

      if Success then
         File.Value.Kind := Unknown;
      end if;
   end Delete;

   ----------------------
   -- Locale_Full_Name --
   ----------------------

   function Locale_Full_Name (File : Virtual_File) return String is
   begin
      if File.Value = null then
         return "";
      else
         --  ??? This is not cached, should it ?
         return Locale_From_UTF8 (File.Value.Full_Name.all);
      end if;
   end Locale_Full_Name;

   ----------------------
   -- Locale_Base_Name --
   ----------------------

   function Locale_Base_Name (File : Virtual_File) return String is
      Base : constant String := Base_Name (File);
   begin
      return Locale_From_UTF8 (Base);
   end Locale_Base_Name;

   ---------------------
   -- Locale_Dir_Name --
   ---------------------

   function Locale_Dir_Name (File : Virtual_File) return String is
      Name : constant String := Dir_Name (File).all;
   begin
      return Locale_From_UTF8 (Name);
   end Locale_Dir_Name;

   ---------------------
   -- Is_Regular_File --
   ---------------------

   function Is_Regular_File (File : Virtual_File) return Boolean is
   begin
      if File.Value = null then
         return False;
      elsif File.Value.Connection = null then
         return Is_Regular_File (Locale_Full_Name (File));
      else
         return Is_Regular_File
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
      end if;
   end Is_Regular_File;

   --------------------
   -- Unchecked_Free --
   --------------------

   procedure Unchecked_Free (Arr : in out File_Array_Access) is
      procedure Internal is new Ada.Unchecked_Deallocation
        (File_Array, File_Array_Access);
   begin
      Internal (Arr);
   end Unchecked_Free;

   -----------------
   -- Is_Writable --
   -----------------

   function Is_Writable (File : Virtual_File) return Boolean is
   begin
      if File.Value = null then
         return False;
      elsif File.Value.Connection /= null then
         return Is_Writable
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));

      else
         return Is_Writable_File (Locale_Full_Name (File));
      end if;
   end Is_Writable;

   ------------------
   -- Is_Directory --
   ------------------

   function Is_Directory (File : Virtual_File) return Boolean is
      Ret : Boolean;
   begin
      if File.Value = null then
         return False;

      elsif File.Value.Connection /= null then
         Ret := Is_Directory
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));

      else
         Ret := Is_Directory (Locale_Full_Name (File));
      end if;

      if Ret then
         File.Value.Kind := Directory;
         Ensure_Directory (File);
      end if;

      return Ret;
   end Is_Directory;

   ----------------------
   -- Is_Symbolic_Link --
   ----------------------

   function Is_Symbolic_Link (File : Virtual_File) return Boolean is
   begin
      if File.Value = null then
         return False;

      elsif File.Value.Connection /= null then
         --  ??? for now, no specific remote test for this,
         --  assume the file is not a symbolic link

         return False;

      else
         return Is_Symbolic_Link (Locale_Full_Name (File));
      end if;
   end Is_Symbolic_Link;

   ----------------------
   -- Is_Absolute_Path --
   ----------------------

   function Is_Absolute_Path (File : Virtual_File) return Boolean is
   begin
      return Is_Absolute_Path
        (File.Value.Full_Name
           (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
   end Is_Absolute_Path;

   --------------------
   -- File_Extension --
   --------------------

   function File_Extension (File : Virtual_File) return UTF8_String is
   begin
      return File_Extension
        (File.Value.Full_Name
           (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
   end File_Extension;

   ---------------
   -- Read_File --
   ---------------

   function Read_File (File : Virtual_File) return String_Access is
   begin
      if File.Value = null then
         return null;
      elsif File.Value.Kind = Directory then
         return null;
      elsif File.Value.Connection = null then
         return Read_File (Full_Name (File).all);
      else
         return Read_File
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
      end if;
   end Read_File;

   ----------------
   -- Write_File --
   ----------------

   function Write_File
     (File   : Virtual_File;
      Append : Boolean := False) return Writable_File
   is
      Tmp : GNAT.OS_Lib.String_Access;
      Fd  : File_Descriptor;
   begin
      if File.Value = null then
         return Invalid_File;

      elsif File.Value.Connection /= null then
         declare
            Current_Dir : constant String := Get_Current_Dir;
            Base        : String_Access;
         begin
            Change_Dir (Temporary_Dir);
            Create_Temp_File (Fd, Base);
            Tmp := new String'(Name_As_Directory (Temporary_Dir) & Base.all);
            Free (Base);
            Change_Dir (Current_Dir);
         end;

      else
         if Append and then Is_Regular_File (Locale_Full_Name (File)) then
            Fd := Open_Read_Write (Locale_Full_Name (File), Binary);
            Lseek (Fd, 0, Seek_End);
         else
            Fd := Create_File (Locale_Full_Name (File), Binary);
         end if;
      end if;

      if Fd = Invalid_FD then
         Free (Tmp);
         return Invalid_File;
      else
         return (File => File, FD => Fd, Filename => Tmp);
      end if;
   end Write_File;

   -----------
   -- Write --
   -----------

   procedure Write
     (File    : in out Writable_File;
      Str     : UTF8_String;
      As_UTF8 : Boolean := True)
   is
      function To_Address is new Ada.Unchecked_Conversion
        (chars_ptr, System.Address);

      procedure C_Free (S : Interfaces.C.Strings.chars_ptr);
      pragma Import (C, C_Free, "free");

      Written : aliased Natural;
      Read    : aliased Natural;
      S       : chars_ptr;

   begin
      if As_UTF8 then
         S := Locale_From_UTF8 (Str, Read'Access, Written'Access);

         if S = Null_Ptr then
            --  Couldn't convert ? Just save the string as is, this is better
            --  than nothing
            Written := Write (File.FD, Str'Address, Str'Length);
         else
            Written := Write (File.FD, To_Address (S), Written);
            C_Free (S);
         end if;

      else
         Written := Write (File.FD, Str'Address, Str'Length);
      end if;

      --  ??? Should raise an exception if we couldn't write all the bytes.
   end Write;

   -----------
   -- Close --
   -----------

   procedure Close (File : in out Writable_File) is
      Success : Boolean;
   begin
      if File.File.Value.Connection /= null then
         Write (File.File.Value.Connection,
                File.File.Value.Full_Name
                  (File.File.Value.Start_Of_Path
                   .. File.File.Value.Full_Name'Last),
                File.Filename.all);
         Close (File.FD);
         Delete_File (File.Filename.all, Success);

      else
         Close (File.FD);
      end if;

      Free (File.Filename);
   end Close;

   ------------------
   -- Set_Writable --
   ------------------

   procedure Set_Writable (File : VFS.Virtual_File; Writable : Boolean) is
      procedure Internal (File : String; Set : Integer);
      pragma Import (C, Internal, "__gps_set_writable");

   begin
      if File.Value.Connection = null then
         Internal
           (Locale_Full_Name (File) & ASCII.NUL, Boolean'Pos (Writable));
      else
         Set_Writable
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last),
            Writable);
      end if;
   end Set_Writable;

   ------------------
   -- Set_Readable --
   ------------------

   procedure Set_Readable (File : VFS.Virtual_File; Readable : Boolean) is
      procedure Internal (File : String; Set : Integer);
      pragma Import (C, Internal, "__gps_set_readable");

   begin
      if File.Value.Connection = null then
         Internal
           (Locale_Full_Name (File) & ASCII.NUL, Boolean'Pos (Readable));
      else
         Set_Readable
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last),
            Readable);
      end if;
   end Set_Readable;

   ---------------------
   -- File_Time_Stamp --
   ---------------------

   function File_Time_Stamp
     (File : Virtual_File) return Ada.Calendar.Time is
   begin
      if File.Value.Connection = null then
         --  This returns No_Time if the file doesn't exist
         return File_Utils.File_Time_Stamp (Locale_Full_Name (File));
      else
         return File_Time_Stamp
           (File.Value.Connection,
            File.Value.Full_Name
              (File.Value.Start_Of_Path .. File.Value.Full_Name'Last));
      end if;
   end File_Time_Stamp;

   ---------------------
   -- Get_Current_Dir --
   ---------------------

   function Get_Current_Dir return Virtual_File is
      File : Virtual_File;
   begin
      if Working_Dir = null then
         File := Create (Locale_To_UTF8
                          (GNAT.Directory_Operations.Get_Current_Dir));
      else
         File := Create (Working_Dir.all);
      end if;
      File.Value.Kind := Directory;
      return File;
   end Get_Current_Dir;

   ----------------------
   -- Ensure_Directory --
   ----------------------

   procedure Ensure_Directory (Dir : Virtual_File) is
      Sep : Character;
      Full : String_Access;
   begin
      if Dir.Value = null then
         return;
      end if;

      if Dir.Value.Connection = null then
         Sep := GNAT.Directory_Operations.Dir_Separator;
      else
         Sep := '/';
      end if;

      if Dir.Value.Full_Name = null then
         return;
      end if;

      if Dir.Value.Full_Name (Dir.Value.Full_Name'Last) /= '/'
        and Dir.Value.Full_Name (Dir.Value.Full_Name'Last) /= '\'
      then
         Full := new String'(Dir.Value.Full_Name.all & Sep);
         Free (Dir.Value.Full_Name);
         Dir.Value.Full_Name := Full;

         if Dir.Value.Normalized_Full /= null then
            Free (Dir.Value.Normalized_Full);
            Ensure_Normalized (Dir);
         end if;

         if Dir.Value.Dir_Name /= null then
            Free (Dir.Value.Dir_Name);
            Dir.Value.Dir_Name := new String'(Full.all);
         end if;
      end if;
   end Ensure_Directory;

   --------------
   -- Get_Root --
   --------------

   function Get_Root (File : Virtual_File) return Virtual_File is
      Dir : Virtual_File;
   begin
      if File.Value = null or else File.Value.Connection = null then
         return Local_Root_Dir;
      else
         Dir := Create (File.Value.Full_Name
                     (File.Value.Full_Name'First .. File.Value.Start_Of_Path));
         Dir.Value.Kind := Directory;
         return Dir;
      end if;
   end Get_Root;

   -------------
   -- Sub_Dir --
   -------------

   function Sub_Dir
     (Dir : Virtual_File; Name : UTF8_String) return Virtual_File
   is
      New_Dir : Virtual_File;
   begin
      Ensure_Directory (Dir);
      New_Dir := Create (Dir.Value.Full_Name.all & Name);
      Ensure_Directory (New_Dir);

      if Is_Directory (New_Dir) then
         return New_Dir;
      else
         return No_File;
      end if;
   end Sub_Dir;

   ----------------
   -- Change_Dir --
   ----------------

   procedure Change_Dir (Dir : Virtual_File) is
      Result : Boolean;
   begin
      if Dir.Value = null then
         Raise_Exception (VFS_Directory_Error'Identity, "Dir is No_File");
      end if;

      if Dir.Value.Connection = null then
         GNAT.Directory_Operations.Change_Dir
           (Locale_From_UTF8 (Full_Name (Dir).all));

         if Working_Dir /= null then
            Free (Working_Dir);
            Working_Dir := null;
         end if;

      else
         Result := Is_Directory (Dir);

         if Result then
            if Working_Dir /= null then
               Free (Working_Dir);
            end if;
            Working_Dir := new String'(Full_Name (Dir).all);
         else
            Raise_Exception (VFS_Directory_Error'Identity,
                             "Dir is not a directory");
         end if;
      end if;

   exception
      when E : GNAT.Directory_Operations.Directory_Error =>
         Raise_Exception (VFS_Directory_Error'Identity,
                          Exception_Message (E));
   end Change_Dir;

   --------------
   -- Make_Dir --
   --------------

   procedure Make_Dir (Dir : Virtual_File) is
      Result : Boolean;
   begin
      if Dir.Value = null then
         Raise_Exception (VFS_Directory_Error'Identity, "Dir is No_File");
      end if;

      if Dir.Value.Connection /= null then
         GNAT.Directory_Operations.Make_Dir
           (Locale_From_UTF8 (Full_Name (Dir).all));
      else
         Result := Make_Dir
           (Dir.Value.Connection,
            Dir.Value.Full_Name
              (Dir.Value.Start_Of_Path .. Dir.Value.Full_Name'Last));

         if not Result then
            Raise_Exception (VFS_Directory_Error'Identity,
                             "Dir cannot be created");
         end if;
      end if;

      Dir.Value.Kind := Directory;

   exception
      when E : GNAT.Directory_Operations.Directory_Error =>
         Raise_Exception (VFS_Directory_Error'Identity,
                          Exception_Message (E));
   end Make_Dir;

   ------------------------
   -- Make_Dir_Recursive --
   ------------------------

   procedure Make_Dir_Recursive (Dir : Virtual_File) is
      Result : Boolean;
   begin
      if Dir.Value = null then
         Raise_Exception (VFS_Directory_Error'Identity, "Dir is No_File");
      end if;

      if Dir.Value.Connection = null then
         Make_Dir_Recursive (Locale_From_UTF8 (Full_Name (Dir).all));
      else
         declare
            Name : constant String :=
              Dir.Value.Full_Name
                (Dir.Value.Start_Of_Path .. Dir.Value.Full_Name'Last);
            Last : Natural := Name'First + 1;

         begin
            --  set to true by default (do not raise exception if no
            --  directory is created)

            Result := True;

            while Last < Name'Last loop
               while Last <= Name'Last
                 and then Name (Last) /= '/'
               loop
                  Last := Last + 1;
               end loop;

               if not Is_Directory (Dir.Value.Connection,
                                    Name (Name'First .. Last)) then
                  Result := Make_Dir (Dir.Value.Connection,
                                      Name (Name'First .. Last));
                  exit when not Result;
               end if;

               Last := Last + 1;
            end loop;

            if not Result then
               Raise_Exception (VFS_Directory_Error'Identity,
                                "Cannot create " & Name (Name'First .. Last));
            end if;
         end;
      end if;

      Dir.Value.Kind := Directory;

   exception
      when E : GNAT.Directory_Operations.Directory_Error =>
         Raise_Exception (VFS_Directory_Error'Identity,
                          Exception_Message (E));
   end Make_Dir_Recursive;

   ----------------
   -- Remove_Dir --
   ----------------

   procedure Remove_Dir
     (Dir       : Virtual_File;
      Recursive : Boolean := False)
   is
      Result : Boolean;
   begin
      if Dir.Value = null then
         Raise_Exception (VFS_Directory_Error'Identity, "Dir is No_File");
      end if;

      if Dir.Value.Connection = null then
         GNAT.Directory_Operations.Remove_Dir
           (Locale_From_UTF8 (Full_Name (Dir).all),
            Recursive);

      else
         Result := Remove_Dir
           (Dir.Value.Connection,
            Dir.Value.Full_Name
              (Dir.Value.Start_Of_Path .. Dir.Value.Full_Name'Last),
            Recursive);

         if not Result then
            Raise_Exception (VFS_Directory_Error'Identity,
                             "Cannot remove directory " &
                             Locale_Full_Name (Dir));
         end if;
      end if;

      if Result then
         Dir.Value.Kind := Unknown;
      end if;

   exception
      when E : GNAT.Directory_Operations.Directory_Error =>
         Raise_Exception (VFS_Directory_Error'Identity,
                          Exception_Message (E));
   end Remove_Dir;

   ----------
   -- Read --
   ----------

   function Read_Dir (Dir : in Virtual_File) return File_Array_Access is
      Nb_Files  : Natural := 0;
      Tmp       : File_Array_Access;
      F_Array   : File_Array_Access;
      Local_Dir : GNAT.Directory_Operations.Dir_Type;
      Name      : String (1 .. 1024);
      Last      : Natural;

   begin
      if Dir.Value = null then
         Raise_Exception (VFS_Directory_Error'Identity, "Dir is No_File");
      end if;

      Ensure_Directory (Dir);

      if not Is_Directory (Dir) then
         Raise_Exception (VFS_Directory_Error'Identity,
                          "Dir is not a directory");
      end if;

      if Dir.Value.Connection = null then
         GNAT.Directory_Operations.Open
           (Local_Dir,
            Locale_From_UTF8 (Full_Name (Dir).all));
         --  let's start with 128 items
         F_Array := new File_Array (1 .. 128);

         loop
            GNAT.Directory_Operations.Read (Local_Dir, Name, Last);
            exit when Last = 0;
            Nb_Files := Nb_Files + 1;

            --  array too small. let's double it.
            if Nb_Files > F_Array'Last then
               Tmp := F_Array;
               F_Array := new File_Array (1 .. Tmp'Last * 2);
               F_Array (1 .. Tmp'Last) := Tmp.all;
               Unchecked_Free (Tmp);
            end if;

            F_Array (Nb_Files) := Create (Full_Name (Dir, True).all &
                                          Name (1 .. Last));
         end loop;

         GNAT.Directory_Operations.Close (Local_Dir);

         Tmp := F_Array;
         F_Array := new File_Array (1 .. Nb_Files);
         F_Array.all := Tmp (1 .. Nb_Files);
         Unchecked_Free (Tmp);

      else
         declare
            List : GNAT.OS_Lib.String_List := Read_Dir
              (Dir.Value.Connection,
               Dir.Value.Full_Name
                 (Dir.Value.Start_Of_Path .. Dir.Value.Full_Name'Last));
         begin
            F_Array := new File_Array (1 .. List'Length);
            Nb_Files := List'Length;

            for J in List'Range loop
               F_Array (J) := Create (Full_Name (Dir).all &
                                      List (List'First + J - 1).all);
               Free (List (J));
            end loop;
         end;
      end if;

      if F_Array /= null then
         return F_Array;
      else
         return null;
      end if;

   exception
      when E : GNAT.Directory_Operations.Directory_Error =>
         Raise_Exception (VFS_Directory_Error'Identity,
                          Exception_Message (E));
   end Read_Dir;

   --------------
   -- Open_Dir --
   --------------

   function Open_Dir (Dir : Virtual_File) return Virtual_Dir is
      VDir : Virtual_Dir;
   begin
      if Dir.Value = null then
         return Invalid_Dir;
      end if;

      VDir.File := Dir;
      VDir.Files_List := Read_Dir (Dir);

      if VDir.Files_List /= null then
         VDir.Current := VDir.Files_List'First - 1;
      end if;

      Dir.Value.Kind := Directory;
      return VDir;

   exception
      when VFS_Directory_Error =>
         return Invalid_Dir;
   end Open_Dir;

   ----------
   -- Read --
   ----------

   procedure Read
     (VDir : in out Virtual_Dir;
      File :    out Virtual_File) is
   begin
      if VDir.Files_List /= null
        and then VDir.Current < VDir.Files_List'Last
      then
         VDir.Current := VDir.Current + 1;
         File := VDir.Files_List (VDir.Current);
      else
         File := No_File;
      end if;
   end Read;

   -----------
   -- Close --
   -----------

   procedure Close (VDir : in out Virtual_Dir) is
   begin
      if VDir.Files_List /= null then
         Unchecked_Free (VDir.Files_List);
      end if;

      VDir := Invalid_Dir;
   end Close;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (Value : in out Contents_Access) is
   begin
      if Value /= null then
         Value.Ref_Count := Value.Ref_Count - 1;

         if Value.Ref_Count = 0 then
            if Value.Connection /= null then
               Close (Value.Connection, GPS_Termination => False);
            end if;

            Free (Value.Full_Name);
            Free (Value.Dir_Name);
            Free (Value.Normalized_Full);
            Unchecked_Free (Value);
         end if;
      end if;
   end Finalize;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (File : in out Virtual_File) is
   begin
      Finalize (File.Value);
   end Finalize;

   ------------
   -- Adjust --
   ------------

   procedure Adjust (File : in out Virtual_File) is
   begin
      if File.Value /= null then
         File.Value.Ref_Count := File.Value.Ref_Count + 1;
      end if;
   end Adjust;

   ---------
   -- "<" --
   ---------

   function "<" (File1, File2 : Virtual_File) return Boolean is
      C1, C2 : Character;
   begin
      if File1 = File2 then
         return False;
      elsif File1.Value = null then
         return True;
      elsif File2.Value = null then
         return False;
      elsif Filenames_Are_Case_Sensitive
        or File1.Value.Connection /= null
        or File2.Value.Connection /= null
      then
         return File1.Value.Full_Name.all < File2.Value.Full_Name.all;
      else
         for C in File1.Value.Full_Name'Range loop
            if C > File2.Value.Full_Name'Last then
               return False;
            end if;

            C1 := To_Lower (File1.Value.Full_Name (C));
            C2 := To_Lower (File2.Value.Full_Name (C));

            if C1 < C2 then
               return True;
            elsif C1 > C2 then
               return False;
            end if;
         end loop;

         return True;
      end if;
   end "<";

   ---------------
   -- Is_Parent --
   ---------------

   function Is_Parent (Parent, Child : Virtual_File) return Boolean is
      C1, C2 : Character;
      Case_Sensitive : Boolean;
   begin
      if Parent.Value = null or Child.Value = null then
         return False;
      elsif Parent.Value.Connection /= Child.Value.Connection then
         return False;
      end if;

      Ensure_Normalized (Parent);
      Ensure_Normalized (Child);

      if Parent.Value.Normalized_Full'Length >
        Child.Value.Normalized_Full'Length then
         return False;
      end if;

      if Filenames_Are_Case_Sensitive
        or Parent.Value.Connection /= null then
         Case_Sensitive := True;
      else
         Case_Sensitive := False;
      end if;

      for C in Parent.Value.Normalized_Full'Range loop
         if Case_Sensitive then
            C1 := Parent.Value.Normalized_Full (C);
            C2 := Child.Value.Normalized_Full (C);
         else
            C1 := To_Lower (Parent.Value.Normalized_Full (C));
            C2 := To_Lower (Child.Value.Normalized_Full (C));
         end if;

         if C1 /= C2 then
            return False;
         end if;
      end loop;

      return True;
   end Is_Parent;

   ----------
   -- Sort --
   ----------

   procedure Sort (Files : in out File_Array) is
      --  ??? Right now, this sorts only on the full name. Do we want to
      --  provide other choices for sorting ?

      procedure Xchg (Op1, Op2 : Natural);
      --  Exchanges two items in the array.

      function Lt (Op1, Op2 : Natural) return Boolean;
      --  Return True if the first item is to be sorted before the second.

      procedure Xchg (Op1, Op2 : Natural) is
         Buffer : Virtual_File;
      begin
         Buffer := Files (Files'First - 1 + Op1);
         Files (Files'First - 1 + Op1) := Files (Files'First - 1 + Op2);
         Files (Files'First - 1 + Op2) := Buffer;
      end Xchg;

      function Lt (Op1, Op2 : Natural) return Boolean is
      begin
         return Files (Files'First - 1 + Op1) <
           Files (Files'First - 1 + Op2);
      end Lt;
   begin
      Sort (Files'Length, Xchg'Unrestricted_Access, Lt'Unrestricted_Access);
   end Sort;

   -----------------------------
   -- Virtual_File_Boxed_Copy --
   -----------------------------

   function Virtual_File_Boxed_Copy
     (Boxed : System.Address) return System.Address
   is
      Value : constant Contents_Access := To_Contents_Access (Boxed);
   begin
      if Value /= null then
         Value.Ref_Count := Value.Ref_Count + 1;
      end if;

      return Boxed;
   end Virtual_File_Boxed_Copy;

   -----------------------------
   -- Virtual_File_Boxed_Free --
   -----------------------------

   procedure Virtual_File_Boxed_Free (Boxed : System.Address) is
      Value : Contents_Access := To_Contents_Access (Boxed);
   begin
      Finalize (Value);
   end Virtual_File_Boxed_Free;

   --------------
   -- Set_File --
   --------------

   procedure Set_File
     (Value : in out Glib.Values.GValue; File : Virtual_File) is
   begin
      Init (Value, Get_Virtual_File_Type);

      if File.Value = null then
         Set_Boxed (Value, System.Null_Address);
      else
         Set_Boxed (Value, File.Value.all'Address);
      end if;
   end Set_File;

   --------------
   -- Get_File --
   --------------

   function Get_File (Value : Glib.Values.GValue) return Virtual_File is
      File : Virtual_File;
   begin
      File.Value := To_Contents_Access (Get_Boxed (Value));

      if File.Value /= null then
         File.Value.Ref_Count := File.Value.Ref_Count + 1;
      end if;

      return File;
   end Get_File;

   ---------------------------
   -- Get_Virtual_File_Type --
   ---------------------------

   function Get_Virtual_File_Type return Glib.GType is
   begin
      if Virtual_File_Type = GType_None then
         Virtual_File_Type := Boxed_Type_Register_Static
           ("Virtual_File", Virtual_File_Boxed_Copy'Access,
            Virtual_File_Boxed_Free'Access);
      end if;

      return Virtual_File_Type;
   end Get_Virtual_File_Type;

end VFS;
