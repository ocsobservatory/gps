-----------------------------------------------------------------------
--                              G P S                                --
--                                                                   --
--                     Copyright (C) 2001-2002                       --
--                            ACT-Europe                             --
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

with Glib;                      use Glib;
with Glib.Object;               use Glib.Object;
with Gtk.Accel_Group;           use Gtk.Accel_Group;
with Gdk.Types;                 use Gdk.Types;
with Gdk.Types.Keysyms;         use Gdk.Types.Keysyms;
with Gtk.Enums;
with Gtk.Main;                  use Gtk.Main;
with Gtk.Menu;                  use Gtk.Menu;
with Gtk.Menu_Item;             use Gtk.Menu_Item;
with Gtk.Stock;                 use Gtk.Stock;

with Glide_Intl;                use Glide_Intl;

with GVD.Preferences;           use GVD.Preferences;
with GVD.Status_Bar;            use GVD.Status_Bar;

with Glide_Kernel;              use Glide_Kernel;
with Glide_Kernel.Console;      use Glide_Kernel.Console;
with Glide_Kernel.Modules;      use Glide_Kernel.Modules;
with Glide_Kernel.Preferences;  use Glide_Kernel.Preferences;
with Glide_Kernel.Project;      use Glide_Kernel.Project;
with Glide_Kernel.Timeout;      use Glide_Kernel.Timeout;
with Language_Handlers;         use Language_Handlers;
with Language_Handlers.Glide;   use Language_Handlers.Glide;
with Prj_API;                   use Prj_API;
with Prj;                       use Prj;
with Src_Info;                  use Src_Info;

with Glide_Main_Window;         use Glide_Main_Window;

with Basic_Types;
with GVD.Dialogs;               use GVD.Dialogs;
with String_Utils;              use String_Utils;
with String_List_Utils;
with GUI_Utils;                 use GUI_Utils;

with GNAT.Expect;               use GNAT.Expect;
pragma Warnings (Off);
with GNAT.Expect.TTY;           use GNAT.Expect.TTY;
pragma Warnings (On);
with GNAT.Regpat;               use GNAT.Regpat;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with GNAT.Case_Util;            use GNAT.Case_Util;

with Traces;                    use Traces;
with Ada.Exceptions;            use Ada.Exceptions;
with Ada.Unchecked_Deallocation;

package body Builder_Module is

   Timeout : constant Guint32 := 50;
   --  Timeout in milliseconds to check the build process

   Timeout_Xref : constant Guint32 := 50;
   --  Timeout in milliseconds to generate the xref information

   Me : constant Debug_Handle := Create (Builder_Module_Name);

   All_Files : constant String := "<all>";
   --  String id used to represent all files.

   type Builder_Module_ID_Record is new Module_ID_Record with record
      Make_Menu  : Gtk_Menu;
      Run_Menu   : Gtk_Menu;
      Build_Item : Gtk_Menu_Item;
      --  The build menu, updated automatically every time the list of main
      --  units changes.

      Output     : String_List_Utils.String_List.List;
      --  The last build output.
   end record;
   --  Data stored with the module id.

   type Builder_Module_ID_Access is access all Builder_Module_ID_Record;

   function Idle_Build (Data : Process_Data) return Boolean;
   --  Called by the Gtk main loop when idle.
   --  Handle on going build.

   type LI_Handler_Iterator_Access_Access is access LI_Handler_Iterator_Access;

   type Compute_Xref_Data is record
      Kernel : Kernel_Handle;
      Iter   : LI_Handler_Iterator_Access_Access;
      LI     : Natural;
   end record;
   type Compute_Xref_Data_Access is access Compute_Xref_Data;

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (LI_Handler_Iterator_Access, LI_Handler_Iterator_Access_Access);

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Compute_Xref_Data, Compute_Xref_Data_Access);

   package Xref_Timeout is new Gtk.Main.Timeout (Compute_Xref_Data_Access);

   procedure Timeout_Xref_Destroy (D : in out Compute_Xref_Data_Access);
   --  Destroy the memory associated with an Xref_Timeout.

   function Timeout_Compute_Xref
     (D : Compute_Xref_Data_Access) return Boolean;
   --  Compute the cross-references for the next files in the project.

   procedure Set_Sensitive_Menus
     (Kernel    : Kernel_Handle;
      Sensitive : Boolean);
   --  Change the sensitive aspect of the build menu items.

   procedure Free (Ar : in out String_List);
   procedure Free (Ar : in out String_List_Access);
   --  Free the memory associate with Ar.

   function Compute_Arguments
     (Kernel  : Kernel_Handle;
      Syntax  : Command_Syntax;
      Project : String;
      File    : String) return Argument_List_Access;
   --  Compute the make arguments following the right Syntax
   --  (gnatmake / make), given a Project and File name.
   --  It is the responsibility of the caller to free the returned object.

   procedure Parse_Compiler_Output
     (Kernel : Kernel_Handle;
      Output : String);
   --  Parse the output of build engine and insert the result
   --    - in the GPS results view if it corresponds to a file location
   --    - in the GPS console if it is a general message.

   --------------------
   -- Menu Callbacks --
   --------------------

   procedure On_Check_Syntax
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Build->Check Syntax menu

   procedure On_Compile
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Build->Compile menu

   procedure On_Build
     (Kernel : access GObject_Record'Class; Data : File_Project_Record);
   --  Build->Make menu.
   --  If Data contains a null file name, then the current file is compiled.

   procedure On_Custom
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Build->Custom... menu

   procedure On_Compute_Xref
     (Object : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Build->Compute Xref information menu

   procedure On_Run
     (Kernel : access GObject_Record'Class; Data : File_Project_Record);
   --  Build->Run menu

   procedure On_Stop_Build
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Build->Stop Build menu

   procedure On_View_Changed
     (K : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Called every time the project view has changed, ie potentially the list
   --  of main units.

   function Compile_Command
     (Kernel  : access Kernel_Handle_Record'Class;
      Command : String;
      Args    : String_List_Utils.String_List.List) return String;
   --  Command handler for the "compile" command.

   procedure Compile_File
     (Kernel : Kernel_Handle;
      File   : String);
   --  Launch a compilation command for File.

   procedure Clear_Compilation_Output (Kernel : Kernel_Handle);
   --  Clear the compiler output, the console, and the result view.

   ------------------------------
   -- Clear_Compilation_Output --
   ------------------------------

   procedure Clear_Compilation_Output (Kernel : Kernel_Handle) is
   begin
      Console.Clear (Kernel);
      Remove_Result_Category (Kernel, -"Builder Results");
      String_List_Utils.String_List.Free
        (Builder_Module_ID_Access (Builder_Module_ID).Output);
   end Clear_Compilation_Output;

   ---------------------------
   -- Parse_Compiler_Output --
   ---------------------------

   procedure Parse_Compiler_Output
     (Kernel : Kernel_Handle;
      Output : String)
   is
      File_Location : constant Pattern_Matcher :=
        Compile (Get_Pref (Kernel, File_Pattern));
      File_Index : constant Integer :=
        Integer (Get_Pref (Kernel, File_Pattern_Index));
      Line_Index : constant Integer :=
        Integer (Get_Pref (Kernel, Line_Pattern_Index));
      Col_Index  : constant Integer :=
        Integer (Get_Pref (Kernel, Column_Pattern_Index));
      Matched    : Match_Array (0 .. 9);
      Start      : Natural := Output'First;
      Last       : Natural;
      Real_Last  : Natural;
      Line       : Natural := 1;
      Column     : Natural := 1;

   begin
      Insert (Kernel, Output, Add_LF => False);
      String_List_Utils.String_List.Append
        (Builder_Module_ID_Access (Builder_Module_ID).Output,
         Output);

      while Start <= Output'Last loop
         --  Parse output line by line and look for file locations

         while Start < Output'Last
           and then (Output (Start) = ASCII.CR
                     or else Output (Start) = ASCII.LF)
         loop
            Start := Start + 1;
         end loop;

         Real_Last := Start;

         while Real_Last < Output'Last
           and then Output (Real_Last + 1) /= ASCII.CR
           and then Output (Real_Last + 1) /= ASCII.LF
         loop
            Real_Last := Real_Last + 1;
         end loop;

         Match (File_Location, Output (Start .. Real_Last), Matched);

         if Matched (0) /= No_Match then
            if Matched (Line_Index) /= No_Match then
               Line := Integer'Value
                 (Output
                    (Matched (Line_Index).First .. Matched (Line_Index).Last));

               if Line <= 0 then
                  Line := 1;
               end if;
            end if;

            if Matched (Col_Index) = No_Match then
               Last := Matched (Line_Index).Last;
            else
               Last := Matched (Col_Index).Last;
               Column := Integer'Value
                 (Output (Matched (Col_Index).First ..
                          Matched (Col_Index).Last));

               if Column <= 0 then
                  Column := 1;
               end if;
            end if;

            Insert_Result
              (Kernel,
               -"Builder Results",
               Output
                 (Matched (File_Index).First .. Matched (File_Index).Last),
               Output (Last + 1 .. Real_Last),
               Positive (Line), Positive (Column), 0);
         end if;

         Start := Real_Last + 1;
      end loop;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end Parse_Compiler_Output;

   -----------------------
   -- Compute_Arguments --
   -----------------------

   function Compute_Arguments
     (Kernel  : Kernel_Handle;
      Syntax  : Command_Syntax;
      Project : String;
      File    : String) return Argument_List_Access
   is
      Result         : Argument_List_Access;
      Vars           : Argument_List_Access :=
        Argument_String_To_List
          (Scenario_Variables_Cmd_Line (Kernel, Syntax));
      Build_Progress : constant Boolean :=
        Get_Pref (Kernel, Show_Build_Progress);
      File_Arg       : String_Access;

   begin
      case Syntax is
         when GNAT_Syntax =>
            --  gnatmake -d -Pproject main -XVAR1=value1 ...

            if File = All_Files then
               File_Arg := new String'("");
            else
               File_Arg := new String'(File);
            end if;

            if Build_Progress then
               Result := new Argument_List'
                 ((new String'("-d"),
                   new String'("-P" & Project),
                   new String'(File)) & Vars.all);
            else
               Result := new Argument_List'
                 ((new String'("-P" & Project),
                   new String'(File)) & Vars.all);
            end if;

         when Make_Syntax =>
            --  make -s -C dir -f Makefile.project build VAR1=value1 ...

            declare
               Lang         : String := Get_Language_From_File
                 (Get_Language_Handler (Kernel), File);
               List         : constant Argument_List :=
                 ((new String'("-s"),
                   new String'("-C"),
                   new String'(Dir_Name (Project)),
                   new String'("-f"),
                   new String'("Makefile." & Base_Name (Project, ".gpr")),
                   new String'("build")) & Vars.all);

            begin
               To_Lower (Lang);

               if Lang = "ada" then
                  --  ??? Should set these values also if Ada is part of the
                  --  supported languages.

                  if File = All_Files then
                     File_Arg := new String'("");
                  else
                     File_Arg :=
                       new String'("ADA_SOURCES=" & Base_Name (File));
                  end if;

                  if Build_Progress then
                     Result := new Argument_List'
                       (List &
                        File_Arg &
                        new String'("ADAFLAGS=-d"));

                  else
                     Result := new Argument_List'(List & File_Arg);
                  end if;

               else
                  Result := new Argument_List'(List);
               end if;
            end;
      end case;

      Basic_Types.Unchecked_Free (Vars);
      return Result;
   end Compute_Arguments;

   ----------
   -- Free --
   ----------

   procedure Free (Ar : in out String_List) is
   begin
      for A in Ar'Range loop
         Free (Ar (A));
      end loop;
   end Free;

   procedure Free (Ar : in out String_List_Access) is
      procedure Free is new
        Ada.Unchecked_Deallocation (String_List, String_List_Access);

   begin
      if Ar /= null then
         Free (Ar.all);
         Free (Ar);
      end if;
   end Free;

   -------------------------
   -- Set_Sensitive_Menus --
   -------------------------

   procedure Set_Sensitive_Menus
     (Kernel    : Kernel_Handle;
      Sensitive : Boolean)
   is
      Build : constant String := '/' & (-"Build") & '/';
   begin
      Set_Sensitive (Find_Menu_Item
        (Kernel, Build & (-"Check Syntax")), Sensitive);
      Set_Sensitive (Find_Menu_Item
        (Kernel, Build & (-"Compile File")), Sensitive);
      Set_Sensitive (Find_Menu_Item (Kernel, Build & (-"Make")), Sensitive);
      Set_Sensitive (Find_Menu_Item
        (Kernel, Build & (-"Interrupt")), not Sensitive);
   end Set_Sensitive_Menus;

   --------------
   -- On_Build --
   --------------

   procedure On_Build
     (Kernel : access GObject_Record'Class; Data : File_Project_Record)
   is
      K            : constant Kernel_Handle := Kernel_Handle (Kernel);
      Top          : constant Glide_Window :=
        Glide_Window (Get_Main_Window (K));
      Fd           : Process_Descriptor_Access;
      Cmd          : String_Access;
      Args         : Argument_List_Access;
      Id           : Timeout_Handler_Id;
      Context      : Selection_Context_Access;
      Prj          : Project_Id;
      Project_View : constant Project_Id := Get_Project_View (K);
      Project_Name : constant String := Get_Project_File_Name (K);
      Langs        : Argument_List := Get_Languages
        (Project_View, Recursive => True);
      Syntax       : Command_Syntax;
      State_Pushed : Boolean := False;

   begin
      To_Lower (Langs (Langs'First).all);

      if Langs'Length = 1 and then Langs (Langs'First).all = "ada" then
         Syntax := GNAT_Syntax;
      else
         Syntax := Make_Syntax;
      end if;

      Free (Langs);

      --  If no file was specified in data, simply compile the current file.

      if Data.Length = 0 then
         Context := Get_Current_Context (K);

         if Context /= null
           and then Context.all in File_Selection_Context'Class
           and then Has_File_Information
             (File_Selection_Context_Access (Context))
         then
            Prj := Get_Project_From_File
              (Project_View,
               File_Information (File_Selection_Context_Access (Context)));

            if Prj = No_Project or else Project_Name = "" then
               Args := new Argument_List'
                 (1 => new String'(File_Information
                         (File_Selection_Context_Access (Context))));
            else
               Args := Compute_Arguments
                 (K, Syntax, Project_Path (Prj),
                  File_Information (File_Selection_Context_Access (Context)));
            end if;

         --  There is no current file, so we can't compile anything

         else
            Console.Insert
              (K, -"No file selected, cannot build", Mode => Error);
            return;
         end if;

      else
         --  Are we using the default internal project ?

         if Get_Project_File_Name (K) = "" then
            case Syntax is
               when GNAT_Syntax =>
                  Args := new Argument_List'(1 => new String'(Data.File));

               when Make_Syntax =>
                  Console.Insert
                    (K, -"You must save the project file before building",
                     Mode => Error);
                  return;
            end case;
         else
            Args := Compute_Arguments
              (K, Syntax, Project_Path (Data.Project), Data.File);
         end if;
      end if;

      --  Ask for saving sources/projects before building

      if Save_All_MDI_Children (K, Force => False) = False then
         Free (Args);
         return;
      end if;

      Clear_Compilation_Output (K);

      Push_State (K, Processing);
      State_Pushed := True;

      case Syntax is
         when GNAT_Syntax =>
            Cmd := new String'(Get_Attribute_Value
              (Project_View, Compiler_Command_Attribute,
               Ide_Package, Default => "gnatmake", Index => "Ada"));

         when Make_Syntax =>
            Cmd := new String'("make");
      end case;

      Console.Insert (K, Cmd.all, Add_LF => False);
      Console.Raise_Console (K);

      for J in Args'First .. Args'Last - 1 loop
         Console.Insert (K, " " & Args (J).all, Add_LF => False);
      end loop;

      Console.Insert (K, " " & Args (Args'Last).all);

      Set_Sensitive_Menus (K, False);

      Top.Interrupted := False;
      Fd := new TTY_Process_Descriptor;
      Non_Blocking_Spawn
        (Fd.all, Cmd.all, Args.all, Buffer_Size => 0, Err_To_Out => True);
      Free (Cmd);
      Free (Args);
      Id := Process_Timeout.Add
        (Timeout, Idle_Build'Access, (K, Fd, null, null, null));

   exception
      when Invalid_Process =>
         Console.Insert (K, -"Invalid command", Mode => Error);
         Pop_State (K);
         Set_Sensitive_Menus (K, True);
         Free (Cmd);
         Free (Args);
         Free (Fd);

      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));

         if State_Pushed then
            Pop_State (K);
         end if;
   end On_Build;

   ---------------------
   -- On_Check_Syntax --
   ---------------------

   procedure On_Check_Syntax
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);
      Context : constant Selection_Context_Access :=
        Get_Current_Context (Kernel);

   begin
      if Context = null
        or else not (Context.all in File_Selection_Context'Class)
      then
         Console.Insert
           (Kernel, -"No file selected, cannot check syntax",
            Mode => Error);
         return;
      end if;

      declare
         Top  : constant Glide_Window :=
           Glide_Window (Get_Main_Window (Kernel));
         File_Context : constant File_Selection_Context_Access :=
           File_Selection_Context_Access (Context);

         File : constant String := Directory_Information (File_Context) &
           File_Information (File_Context);
         Cmd  : constant String := "gnatmake -q -u -gnats " & File;
         Fd   : Process_Descriptor_Access;
         Args : Argument_List_Access;
         Id   : Timeout_Handler_Id;
         Lang : String := Get_Language_From_File
           (Get_Language_Handler (Kernel), File);

      begin
         if File = "" then
            Console.Insert
              (Kernel, -"No file name, cannot check syntax",
               Mode => Error);
            return;
         end if;

         To_Lower (Lang);

         if Lang /= "ada" then
            Console.Insert
              (Kernel, -"Syntax check of non Ada file not yet supported",
               Mode => Error);
            return;
         end if;

         if Save_Child (Kernel, Get_File_Editor (Kernel, File), Force => False)
           = Cancel
         then
            return;
         end if;

         Trace (Me, "On_Check_Syntax: " & Cmd);
         Push_State (Kernel, Processing);

         Clear_Compilation_Output (Kernel);

         Set_Sensitive_Menus (Kernel, False);
         Args := Argument_String_To_List (Cmd);
         Console.Insert (Kernel, Cmd);
         Console.Raise_Console (Kernel);

         Top.Interrupted := False;
         Fd := new Process_Descriptor;
         Non_Blocking_Spawn
           (Fd.all, Args (Args'First).all, Args (Args'First + 1 .. Args'Last),
            Err_To_Out  => True);
         Free (Args);
         Id := Process_Timeout.Add
           (Timeout, Idle_Build'Access, (Kernel, Fd, null, null, null));

      exception
         when Invalid_Process =>
            Console.Insert (Kernel, -"Invalid command", Mode => Error);
            Pop_State (Kernel);
            Set_Sensitive_Menus (Kernel, True);
            Free (Args);
            Free (Fd);
      end;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Check_Syntax;

   ------------------
   -- Compile_File --
   ------------------

   procedure Compile_File
     (Kernel : Kernel_Handle;
      File   : String)
   is
      Top          : constant Glide_Window :=
        Glide_Window (Get_Main_Window (Kernel));
      Project      : constant String := Get_Subproject_Name (Kernel, File);
      Project_View : constant Project_Id := Get_Project_View (Kernel);
      Cmd          : constant String :=
        Get_Attribute_Value
          (Project_View, Compiler_Command_Attribute,
           Ide_Package, Default => "gnatmake", Index => "Ada") & " -q -u ";
      Fd           : Process_Descriptor_Access;
      Args         : Argument_List_Access;
      Id           : Timeout_Handler_Id;
      Lang         : String := Get_Language_From_File
        (Get_Language_Handler (Kernel), File);

   begin
      if File = "" then
         Console.Insert
           (Kernel, -"No file name, cannot compile",
            Mode => Error);
      end if;

      To_Lower (Lang);

      if Lang /= "ada" then
         Console.Insert
           (Kernel, -"Compilation of non Ada file not yet supported",
            Mode => Error);
         return;
      end if;

      if Save_All_MDI_Children (Kernel, Force => False) = False then
         return;
      end if;

      Push_State (Kernel, Processing);

      Clear_Compilation_Output (Kernel);

      Set_Sensitive_Menus (Kernel, False);

      if Project = "" then
         declare
            Full_Cmd : constant String := Cmd & File;
         begin
            Args := Argument_String_To_List (Full_Cmd);
            Console.Insert (Kernel, Full_Cmd);
         end;

      else
         declare
            Full_Cmd : constant String :=
              Cmd & "-P" & Project & " "
                & Scenario_Variables_Cmd_Line (Kernel, GNAT_Syntax)
            & " " & File;

         begin
            Trace (Me, "On_Compile: " & Full_Cmd);
            Args := Argument_String_To_List (Full_Cmd);
            Console.Insert (Kernel, Full_Cmd);
         end;
      end if;

      Console.Raise_Console (Kernel);

      Top.Interrupted := False;
      Fd := new Process_Descriptor;
      Non_Blocking_Spawn
        (Fd.all, Args (Args'First).all, Args (Args'First + 1 .. Args'Last),
         Err_To_Out  => True);
      Free (Args);
      Id := Process_Timeout.Add
        (Timeout, Idle_Build'Access, (Kernel, Fd, null, null, null));

   exception
      when Invalid_Process =>
         Console.Insert (Kernel, -"Invalid command", Mode => Error);
         Pop_State (Kernel);
         Set_Sensitive_Menus (Kernel, True);
         Free (Args);
         Free (Fd);
   end Compile_File;

   ---------------------
   -- Compile_Command --
   ---------------------

   function Compile_Command
     (Kernel  : access Kernel_Handle_Record'Class;
      Command : String;
      Args    : String_List_Utils.String_List.List) return String
   is
      use String_List_Utils.String_List;

      Node : List_Node := First (Args);
   begin
      if Command = "compile" then
         while Node /= Null_Node loop
            Compile_File (Kernel_Handle (Kernel), Data (Node));

            Node := Next (Node);
         end loop;
      elsif Command = "get_build_output" then
         declare
            L : Integer := 0;
         begin
            Node := First
              (Builder_Module_ID_Access (Builder_Module_ID).Output);

            while Node /= Null_Node loop
               L := L + Data (Node)'Length;
               Node := Next (Node);
            end loop;

            if L /= 0 then
               declare
                  S      : String (1 .. L);
                  Length : Natural;
               begin
                  L := 1;
                  Node := First
                    (Builder_Module_ID_Access (Builder_Module_ID).Output);

                  while Node /= Null_Node loop
                     Length := Data (Node)'Length;
                     S (L .. L + Length - 1) := Data (Node);
                     L := L + Length;

                     Node := Next (Node);
                  end loop;

                  return S;
               end;
            end if;
         end;
      end if;

      return "";
   end Compile_Command;

   ----------------
   -- On_Compile --
   ----------------

   procedure On_Compile
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);
      Context : constant Selection_Context_Access :=
        Get_Current_Context (Kernel);

   begin
      if Context = null
        or else not (Context.all in File_Selection_Context'Class)
      then
         Console.Insert
           (Kernel, -"No file selected, cannot compile", Mode => Error);
         return;
      end if;

      Compile_File
        (Kernel,
         File_Information (File_Selection_Context_Access (Context)));

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Compile;

   ---------------
   -- On_Custom --
   ---------------

   procedure On_Custom
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);

      Cmd : constant String := Simple_Entry_Dialog
        (Parent   => Get_Main_Window (Kernel),
         Title    => -"Custom Execution",
         Message  => -"Enter the command to execute:",
         Position => Gtk.Enums.Win_Pos_Mouse,
         History  => Get_History (Kernel),
         Key      => "gps_custom_command");

   begin
      if Cmd = "" or else Cmd (Cmd'First) = ASCII.NUL then
         return;
      end if;

      declare
         Top     : constant Glide_Window :=
           Glide_Window (Get_Main_Window (Kernel));
         Fd      : Process_Descriptor_Access;
         Args    : Argument_List_Access;
         Id      : Timeout_Handler_Id;

      begin
         if Save_All_MDI_Children (Kernel, Force => False) = False then
            return;
         end if;

         Push_State (Kernel, Processing);
         Clear_Compilation_Output (Kernel);
         Set_Sensitive_Menus (Kernel, False);
         Args := Argument_String_To_List (Cmd);

         Console.Insert (Kernel, Cmd);
         Console.Raise_Console (Kernel);

         Top.Interrupted := False;
         Fd := new Process_Descriptor;
         Non_Blocking_Spawn
           (Fd.all, Args (Args'First).all, Args (Args'First + 1 .. Args'Last),
            Err_To_Out  => True);
         Free (Args);
         Id := Process_Timeout.Add
           (Timeout, Idle_Build'Access, (Kernel, Fd, null, null, null));

      exception
         when Invalid_Process =>
            Console.Insert (Kernel, -"Invalid command", Mode => Error);
            Pop_State (Kernel);
            Set_Sensitive_Menus (Kernel, True);
            Free (Args);
            Free (Fd);
      end;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Custom;

   --------------------------
   -- Timeout_Xref_Destroy --
   --------------------------

   procedure Timeout_Xref_Destroy (D : in out Compute_Xref_Data_Access) is
   begin
      Pop_State (D.Kernel);
      Free (D.Iter.all);
      Unchecked_Free (D.Iter);
      Unchecked_Free (D);
   end Timeout_Xref_Destroy;

   --------------------------
   -- Timeout_Compute_Xref --
   --------------------------

   function Timeout_Compute_Xref
     (D : Compute_Xref_Data_Access) return Boolean
   is
      Handler      : constant Glide_Language_Handler :=
        Glide_Language_Handler (Get_Language_Handler (D.Kernel));
      Num_Handlers : constant Natural := LI_Handlers_Count (Handler);
      Not_Finished : Boolean;
      LI           : LI_Handler;
      New_Handler  : Boolean := False;

   begin
      if D.LI /= 0 and then D.Iter.all /= null then
         Continue (D.Iter.all.all, Not_Finished);
      else
         Not_Finished := True;
      end if;

      while Not_Finished loop
         D.LI := D.LI + 1;

         if D.LI > Num_Handlers then
            Insert (D.Kernel, -"Finished parsing all source files");
            return False;
         end if;

         Free (D.Iter.all);

         LI := Get_Nth_Handler (Handler, D.LI);
         if LI /= null then
            New_Handler := True;
            D.Iter.all := new LI_Handler_Iterator'Class'
              (Generate_LI_For_Project
                 (Handler      => LI,
                  Root_Project => Get_Project_View (D.Kernel),
                  Project      => Get_Project_View (D.Kernel),
                  Recursive    => True));
            Continue (D.Iter.all.all, Not_Finished);
         end if;
      end loop;

      if New_Handler then
         Insert (D.Kernel, -"Parsing source files for "
                 & Get_LI_Name (Handler, D.LI));
      end if;

      return True;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
         Insert (D.Kernel, "Finished parsing all source files");
         return False;
   end Timeout_Compute_Xref;

   ---------------------
   -- On_Compute_Xref --
   ---------------------

   procedure On_Compute_Xref
     (Object : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Object);
      Id      : Timeout_Handler_Id;

   begin
      Push_State (Kernel, Processing);
      Id := Xref_Timeout.Add
        (Timeout_Xref, Timeout_Compute_Xref'Access,
         new Compute_Xref_Data'(Kernel, new LI_Handler_Iterator_Access, 0),
         Timeout_Xref_Destroy'Access);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Compute_Xref;

   ----------------
   -- Idle_Build --
   ----------------

   function Idle_Build (Data : Process_Data) return Boolean is
      Kernel  : Kernel_Handle renames Data.Kernel;
      Fd      : Process_Descriptor_Access := Data.Descriptor;

      Top          : constant Glide_Window :=
        Glide_Window (Get_Main_Window (Kernel));
      Matched      : Match_Array (0 .. 3);
      Result       : Expect_Match;
      Matcher      : constant Pattern_Matcher := Compile
        ("completed ([0-9]+) out of ([0-9]+) \((.*)%\)\.\.\.$",
         Multiple_Lines);
      Timeout      : Integer := 1;
      Line_Matcher : constant Pattern_Matcher := Compile (".+");
      Buffer       : String_Access := new String (1 .. 1024);
      Buffer_Pos   : Natural := Buffer'First;
      Min_Size     : Natural;
      New_Size     : Natural;
      Tmp          : String_Access;
      Status       : Integer;

   begin
      if Top.Interrupted then
         Interrupt (Fd.all);
         Console.Insert (Kernel, "<^C>");
         Top.Interrupted := False;
         Print_Message
           (Top.Statusbar, GVD.Status_Bar.Help, -"Interrupting build...");
         Timeout := 10;
      end if;

      loop
         Expect (Fd.all, Result, Line_Matcher, Timeout => Timeout);

         exit when Result = Expect_Timeout;

         declare
            S : constant String := Strip_CR (Expect_Out (Fd.all));
         begin
            Match (Matcher, S, Matched);

            if Matched (0) = No_Match then
               --  Coalesce all the output into one single chunck, which is
               --  much faster to display in the console.

               Min_Size := Buffer_Pos + S'Length;

               if Buffer'Last < Min_Size then
                  New_Size := Buffer'Length * 2;

                  while New_Size < Min_Size loop
                     New_Size := New_Size * 2;
                  end loop;

                  Tmp := new String (1 .. New_Size);
                  Tmp (1 .. Buffer_Pos - 1) := Buffer (1 .. Buffer_Pos - 1);
                  Free (Buffer);
                  Buffer := Tmp;
               end if;

               Buffer (Buffer_Pos .. Buffer_Pos + S'Length - 1) := S;
               Buffer_Pos := Buffer_Pos + S'Length;

            else
               Set_Fraction
                 (Top.Statusbar,
                  Gdouble'Value
                    (S (Matched (3).First .. Matched (3).Last)) / 100.0);
               Set_Progress_Text
                 (Top.Statusbar, S (S'First + 1 .. Matched (2).Last));
            end if;
         end;
      end loop;

      if Buffer_Pos /= Buffer'First then
         Parse_Compiler_Output
           (Kernel, Buffer (Buffer'First .. Buffer_Pos - 1));
      end if;

      Free (Buffer);

      return True;

   exception
      when Process_Died =>
         if Buffer_Pos /= Buffer'First then
            Parse_Compiler_Output
              (Kernel,
               Buffer (Buffer'First .. Buffer_Pos - 1) & Expect_Out (Fd.all));
         end if;

         Free (Buffer);
         Set_Fraction (Top.Statusbar, 0.0);
         Set_Progress_Text (Top.Statusbar, "");
         Parse_Compiler_Output (Kernel, Expect_Out (Fd.all));
         Close (Fd.all, Status);

         if Status = 0 then
            Console.Insert
              (Kernel, ASCII.LF & (-"successful compilation/build"));
            Compilation_Finished (Kernel, "");
         else
            Console.Insert
              (Kernel,
               ASCII.LF & (-"process exited with status ") & Image (Status));
         end if;

         Pop_State (Kernel);
         Set_Sensitive_Menus (Kernel, True);
         Free (Fd);

         return False;

      when E : others =>
         Free (Buffer);
         Pop_State (Kernel);
         Set_Sensitive_Menus (Kernel, True);
         Close (Fd.all);
         Free (Fd);
         Set_Fraction (Top.Statusbar, 0.0);
         Set_Progress_Text (Top.Statusbar, "");
         Trace (Me, "Unexpected exception: " & Exception_Information (E));

         return False;
   end Idle_Build;

   ------------
   -- On_Run --
   ------------

   procedure On_Run
     (Kernel : access GObject_Record'Class; Data : File_Project_Record)
   is
      K       : constant Kernel_Handle := Kernel_Handle (Kernel);
      Active  : aliased Boolean := False;
      Args    : Argument_List_Access;
      Exec    : String_Access;
      Success : Boolean;

   begin
      if Data.Length = 0 then
         declare
            Command : constant String := Display_Entry_Dialog
              (Parent        => Get_Main_Window (K),
               Title         => -"Run Command",
               Message       => -"Enter the command to run:",
               Check_Msg     => -"Use external terminal",
               Key           => "gps_run_cmd",
               History       => Get_History (K),
               Button_Active => Active'Unchecked_Access);

         begin
            if Command = ""
              or else Command (Command'First) = ASCII.NUL
            then
               return;
            else
               if Active then
                  Args := Argument_String_To_List
                    (Get_Pref (K, Execute_Command) & ' ' & Command);
               else
                  Args := Argument_String_To_List (Command);
               end if;

               Exec := Locate_Exec_On_Path (Args (1).all);

               if Exec = null then
                  Insert (K, -"Could not locate executable on path: "
                            & Args (1).all);
               else
                  Launch_Process
                    (K, Exec.all, Args (2 .. Args'Last), -"Run: " & Command,
                     null, null, "", Success, True);
                  Free (Exec);
               end if;

               Free (Args);
            end if;
         end;

      else
         declare
            Arguments : constant String := Display_Entry_Dialog
              (Parent        => Get_Main_Window (K),
               Title         => -"Arguments Selection",
               Message       => -"Enter the arguments to your application:",
               Check_Msg     => -"Use external terminal",
               Key           => "gps_run_args",
               History       => Get_History (K),
               Button_Active => Active'Unchecked_Access);

         begin
            if Arguments = ""
              or else Arguments (Arguments'First) /= ASCII.NUL
            then
               if Active then
                  Args := Argument_String_To_List
                    (Get_Pref (K, Execute_Command) & ' ' &
                     Executables_Directory (Data.Project) & Data.File & ' ' &
                     Arguments);
                  Launch_Process
                    (K, Args (1).all, Args (2 .. Args'Last),
                     -"Run: " & Data.File & ' ' & Arguments,
                     null, null, "", Success, True);

               else
                  Args := Argument_String_To_List (Arguments);
                  Launch_Process
                    (K, Executables_Directory (Data.Project) & Data.File,
                     Args.all, -"Run: " & Data.File & ' ' & Arguments,
                     null, null, "", Success, True);
               end if;

               Free (Args);
            end if;
         end;
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Run;

   -------------------
   -- On_Stop_Build --
   -------------------

   procedure On_Stop_Build
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (Widget);

      Top : constant Glide_Window := Glide_Window (Get_Main_Window (Kernel));
   begin
      Top.Interrupted := True;
      Console.Raise_Console (Kernel);
   end On_Stop_Build;

   ---------------------
   -- On_View_Changed --
   ---------------------

   procedure On_View_Changed
     (K : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      pragma Unreferenced (K);

      Builder_Module : constant Builder_Module_ID_Access :=
        Builder_Module_ID_Access (Builder_Module_ID);
      Mitem        : Gtk_Menu_Item;
      Menu1        : Gtk_Menu renames Builder_Module.Make_Menu;
      Menu2        : Gtk_Menu renames Builder_Module.Run_Menu;
      Iter         : Imported_Project_Iterator := Start (Get_Project (Kernel));
      Has_Child    : Boolean := False;

   begin
      --  Remove all existing menus and dynamic accelerators

      if Builder_Module.Build_Item /= null then
         Remove_Accelerator
           (Builder_Module.Build_Item,
            Get_Default_Accelerators (Kernel), GDK_F4, 0);
      end if;

      Remove_All_Children (Menu1);
      Remove_All_Children (Menu2);

      --  Add all the main units from all the imported projects.

      while Current (Iter) /= No_Project loop
         declare
            Mains : Argument_List := Get_Attribute_Value
              (Current (Iter), Attribute_Name => Main_Attribute);
         begin
            for M in Mains'Range loop
               Gtk_New (Mitem, Mains (M).all);
               Append (Menu1, Mitem);
               File_Project_Cb.Object_Connect
                 (Mitem, "activate",
                  File_Project_Cb.To_Marshaller (On_Build'Access),
                  Slot_Object => Kernel,
                  User_Data => File_Project_Record'
                    (Length  => Mains (M)'Length,
                     Project => Current (Iter),
                     File    => Mains (M).all));

               --  The first item in the make menu should have a key binding

               if not Has_Child then
                  Add_Accelerator
                    (Mitem, "activate", Get_Default_Accelerators (Kernel),
                     GDK_F4, 0, Gtk.Accel_Group.Accel_Visible);
                  Builder_Module.Build_Item := Mitem;
               end if;

               Has_Child := True;

               declare
                  Exec : constant String := Base_Name (Mains (M).all,
                     GNAT.Directory_Operations.File_Extension
                       (Mains (M).all));
               begin
                  Gtk_New (Mitem, Exec);
                  Append (Menu2, Mitem);
                  File_Project_Cb.Object_Connect
                    (Mitem, "activate",
                     File_Project_Cb.To_Marshaller (On_Run'Access),
                     Slot_Object => Kernel,
                     User_Data => File_Project_Record'
                       (Length  => Exec'Length,
                        Project => Current (Iter),
                        File    => Exec));
               end;
            end loop;

            Free (Mains);
         end;

         Next (Iter);
      end loop;

      --  No main program ?

      Gtk_New (Mitem, -"<current file>");
      Append (Menu1, Mitem);
      File_Project_Cb.Object_Connect
        (Mitem, "activate",
         File_Project_Cb.To_Marshaller (On_Build'Access),
         Slot_Object => Kernel,
         User_Data => File_Project_Record'
           (Length  => 0,
            Project => No_Project,
            File    => ""));

      if not Has_Child then
         Add_Accelerator
           (Mitem, "activate", Get_Default_Accelerators (Kernel),
            GDK_F4, 0, Gtk.Accel_Group.Accel_Visible);
         Builder_Module.Build_Item := Mitem;
      end if;

      Gtk_New (Mitem, -"All");
      Append (Menu1, Mitem);
      File_Project_Cb.Object_Connect
        (Mitem, "activate",
         File_Project_Cb.To_Marshaller (On_Build'Access),
         Slot_Object => Kernel,
         User_Data => File_Project_Record'
           (Length  => All_Files'Length,
            Project => Get_Project_View (Kernel),
            File    => All_Files));

      Gtk_New (Mitem, -"Custom...");
      Append (Menu1, Mitem);
      Kernel_Callback.Connect
        (Mitem, "activate",
         Kernel_Callback.To_Marshaller (On_Custom'Access),
         User_Data => Kernel);
      Add_Accelerator
        (Mitem, "activate", Get_Default_Accelerators (Kernel),
         GDK_F9, 0, Gtk.Accel_Group.Accel_Visible);

      --  Should be able to run any program

      Gtk_New (Mitem, -"Custom...");
      Append (Menu2, Mitem);
      File_Project_Cb.Object_Connect
        (Mitem, "activate",
         File_Project_Cb.To_Marshaller (On_Run'Access),
         Slot_Object => Kernel,
         User_Data   => File_Project_Record'
           (Length => 0, Project => Current (Iter), File => ""));

      Show_All (Menu1);
      Show_All (Menu2);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_View_Changed;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
   is
      Build : constant String := '/' & (-"Build") & '/';
      Mitem : Gtk_Menu_Item;
      Menu  : Gtk_Menu;
   begin
      --  This memory is allocated once, and lives as long as the application.

      Builder_Module_ID := new Builder_Module_ID_Record;
      Register_Module
        (Module       => Builder_Module_ID,
         Kernel       => Kernel,
         Module_Name  => Builder_Module_Name,
         Priority     => Default_Priority);

      Register_Menu (Kernel, "/_" & (-"Build"), Ref_Item => -"Debug");
      Register_Menu (Kernel, Build, -"Check _Syntax", "",
                     On_Check_Syntax'Access);
      Register_Menu (Kernel, Build, -"_Compile File", "",
                     On_Compile'Access, null, GDK_F4, Shift_Mask);

      --  Dynamic make menu

      Mitem := Register_Menu (Kernel, Build, -"_Make", "", null);
      Gtk_New (Menu);
      Builder_Module_ID_Record (Builder_Module_ID.all).Make_Menu := Menu;
      Set_Submenu (Mitem, Menu);

      Register_Menu
        (Kernel, Build, -"Recompute C/C++ _Xref info", "",
         On_Compute_Xref'Access);

      Gtk_New (Mitem);
      Register_Menu (Kernel, Build, Mitem);

      --  Dynamic run menu
      Mitem := Register_Menu
        (Kernel, Build, -"_Run", Stock_Execute, null);
      Gtk_New (Menu);
      Builder_Module_ID_Record (Builder_Module_ID.all).Run_Menu := Menu;
      Set_Submenu (Mitem, Menu);

      Gtk_New (Mitem);
      Register_Menu (Kernel, Build, Mitem);
      Set_Sensitive
        (Register_Menu
          (Kernel, Build, -"_Interrupt", Stock_Stop, On_Stop_Build'Access),
         False);

      Kernel_Callback.Connect
        (Kernel, "project_view_changed",
         Kernel_Callback.To_Marshaller (On_View_Changed'Access),
         User_Data => Kernel_Handle (Kernel));

      Register_Command
        (Kernel,
         "compile",
         "Usage:  compile file1 [file2] ..." & ASCII.LF
         & "  compiles a list of files from the project.",
         Compile_Command'Access);

      Register_Command
        (Kernel,
         "get_build_output",
         "Usage:  get_build_output" & ASCII.LF
         & "  returns the last compilation results.",
         Compile_Command'Access);

   end Register_Module;

end Builder_Module;
