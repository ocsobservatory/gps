-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                      Copyright (C) 2008, AdaCore                  --
--                                                                   --
-- GPS is free  software; you can  redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with System.OS_Lib;             use System.OS_Lib;

with Glib;                      use Glib;
with Gtk.Button;                use Gtk.Button;
with Gtk.Check_Button;          use Gtk.Check_Button;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.Handlers;              use Gtk.Handlers;
with Gtk.Image;                 use Gtk.Image;
with Gtk.Label;                 use Gtk.Label;
with Gtk.Stock;                 use Gtk.Stock;
with Gtk.Table;                 use Gtk.Table;
with Gtk.Toggle_Button;         use Gtk.Toggle_Button;
with Gtk.Tooltips;              use Gtk.Tooltips;
with Gtk.Widget;                use Gtk.Widget;
with Gtk.Window;                use Gtk.Window;
with Gtkada.Dialogs;            use Gtkada.Dialogs;
with Gtkada.File_Selector;      use Gtkada.File_Selector;

with Dualcompilation;           use Dualcompilation;
with GNATCOLL.VFS;              use GNATCOLL.VFS;
with GPS.Intl;                  use GPS.Intl;
with GPS.Kernel.Project;        use GPS.Kernel.Project;
with Projects;                  use Projects;
with Traces;                    use Traces;

package body Dualcompilation_Dialog is

   package Dualc_Callback is new Gtk.Handlers.User_Callback
     (Gtk_Widget_Record, Dualc_Dialog);

   type Entry_Callback_Data is record
      The_Entry : Gtk_Entry;
      Dialog    : Dualc_Dialog;
   end record;

   package Entry_Callback is new Gtk.Handlers.User_Callback
     (Gtk_Widget_Record, Entry_Callback_Data);

   procedure Activate_Toggled
     (Toggle : access Gtk_Widget_Record'Class;
      Dialog : Dualc_Dialog);
   --  Called when the 'Activate' check button is toggled

   procedure Xrefs_Toggled
     (Toggle : access Gtk_Widget_Record'Class;
      Dialog : Dualc_Dialog);
   --  Called when the 'Activate' check button is toggled

   procedure On_Browse
     (Button : access Gtk_Widget_Record'Class;
      Data   : Entry_Callback_Data);
   --  Browse for a directory, then fill the GEntry

   -------------
   -- Toggled --
   -------------

   procedure Activate_Toggled
     (Toggle : access Gtk_Widget_Record'Class;
      Dialog : Dualc_Dialog)
   is
   begin
      Dialog.Active := Get_Active (Gtk_Check_Button (Toggle));
      Set_Sensitive (Dialog.Frame, Dialog.Active);

   exception
      when E : others =>
         Trace (Exception_Handle, E);
   end Activate_Toggled;

   -------------------
   -- Xrefs_Toggled --
   -------------------

   procedure Xrefs_Toggled
     (Toggle : access Gtk_Widget_Record'Class;
      Dialog : Dualc_Dialog)
   is
   begin
      Dialog.Xrefs_Subdir := Get_Active (Gtk_Check_Button (Toggle));

   exception
      when E : others =>
         Trace (Exception_Handle, E);
   end Xrefs_Toggled;

   ---------------
   -- On_Browse --
   ---------------

   procedure On_Browse
     (Button : access Gtk_Widget_Record'Class;
      Data   : Entry_Callback_Data)
   is
      Current_Dir : constant String :=
                      Get_Text (Data.The_Entry);
      Start_Dir   : Virtual_File;
   begin
      if Current_Dir /= "" then
         Start_Dir := Create (Current_Dir);

         if not Is_Directory (Start_Dir) then
            Start_Dir := GNATCOLL.VFS.Get_Current_Dir;
         end if;
      else
         Start_Dir := GNATCOLL.VFS.Get_Current_Dir;
      end if;

      declare
         Dir : constant GNATCOLL.VFS.Virtual_File :=
                 Select_Directory
                   (Base_Directory => Start_Dir,
                    Parent         => Gtk_Window (Get_Toplevel (Button)));
         Compiler : constant String :=
                      Projects.Get_Attribute_Value
                        (GPS.Kernel.Project.Get_Project (Data.Dialog.Kernel),
                         Projects.Compiler_Command_Attribute,
                         Default => "gnatmake",
                         Index   => "Ada");
         Exec     : String_Access;
      begin
         if Dir /= No_File then
            Exec := Locate_Exec (Compiler, Dir.Full_Name.all);

            if Exec /= null then
               --  OK, we could locate a valid compiler.
               Free (Exec);
               Set_Text (Data.The_Entry, Dir.Full_Name.all);

            else
               --  No compiler found: let's display an error.
               declare
                  Resp : Gtkada.Dialogs.Message_Dialog_Buttons;
               begin
                  Resp := Gtkada.Dialogs.Message_Dialog
                    (-("The selected path does not contain a compiler." &
                       ASCII.LF &
                       "Are you sure you want to use this path ?"),
                     Dialog_Type    => Gtkada.Dialogs.Error,
                     Buttons        => Button_OK + Button_Cancel,
                     Title          => -"Invalid compiler path",
                     Parent         => Gtk_Window (Data.Dialog));

                  if Resp = Button_OK then
                     Set_Text (Data.The_Entry, Dir.Full_Name.all);
                  end if;
               end;
            end if;
         end if;
      end;

   exception
      when E : others =>
         Trace (Exception_Handle, E);
   end On_Browse;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Widget            : out Dualc_Dialog;
      Kernel            : access GPS.Kernel.Kernel_Handle_Record'Class;
      Active            : Boolean;
      Tools_Path        : String;
      Use_Xrefs_Subdirs : Boolean;
      Compiler_Path     : String)
   is
      Check  : Gtk_Check_Button;
      Dead   : Gtk_Widget;
      Table  : Gtk_Table;
      Label  : Gtk_Label;
      Browse : Gtk_Button;
      Pix    : Gtk_Image;
      Tips   : constant Gtk_Tooltips := GPS.Kernel.Get_Tooltips (Kernel);
      pragma Unreferenced (Dead);

   begin
      Widget := new Dualc_Dialog_Record;
      Widget.Kernel       := Kernel_Handle (Kernel);
      Widget.Active       := Active;
      Widget.Xrefs_Subdir := Use_Xrefs_Subdirs;

      Initialize
        (Widget,
         Title  => -"Dual compilation setup",
         Parent => GPS.Kernel.Get_Main_Window (Kernel),
         Flags  => Modal);

      Dead := Widget.Add_Button (Gtk.Stock.Stock_Ok, Gtk_Response_OK);
      Dead := Widget.Add_Button (Gtk.Stock.Stock_Cancel, Gtk_Response_Cancel);

      Gtk_New (Check, -"Activate the dual compilation mode");
      Show_All (Check);
      Set_Active (Check, Widget.Active);
      Widget.Get_Vbox.Add (Check);
      Dualc_Callback.Connect
        (Check, Signal_Toggled, Activate_Toggled'Access, Widget);

      Gtk_New (Widget.Frame, -"Paths");
      Set_Sensitive (Widget.Frame, Widget.Active);
      Show_All (Widget.Frame);
      Widget.Get_Vbox.Add (Widget.Frame);

      Gtk_New (Table, Rows => 3, Columns => 3, Homogeneous => False);
      Show_All (Table);
      Add (Widget.Frame, Table);

      Gtk_New (Label, -"Compiler path");
      Set_Alignment (Label, 1.0, 0.5);
      Show_All (Label);
      Attach (Table, Label, 0, 1, 0, 1);

      Gtk_New (Widget.Compiler_Entry);
      Set_Text (Widget.Compiler_Entry, Compiler_Path);
      Show_All (Widget.Compiler_Entry);
      Attach (Table, Widget.Compiler_Entry, 1, 2, 0, 1);
      Set_Tip
        (Tips, Widget.Compiler_Entry,
         -("This path will be used to spawn all code generation actions." &
           ASCII.LF &
           "In particular gnatmake, gprbuild, gcc, gdb, gcov" &
           " will be searched for in this path." &
           ASCII.LF &
           "To compile your project with a specific version of a compiler," &
           " please choose its bin directory here." &
           ASCII.LF & ASCII.LF &
           "Note concerning the interraction with the remote mode:" &
           ASCII.LF &
           "In case you have defined a build server for your project, then " &
           "this path will be ignored. However, the dual compilation mode " &
           "still applies, as actions that would normally execute with this " &
           "path will continue to be executed on the remote host, while " &
           "actions that are executed using the tools path will be executed " &
           "locally."));

      Gtk_New (Label, -"Tools path");
      Set_Alignment (Label, 1.0, 0.5);
      Show_All (Label);
      Attach (Table, Label, 0, 1, 1, 2);

      Gtk_New (Widget.Tools_Entry);
      Set_Text (Widget.Tools_Entry, Tools_Path);
      Show_All (Widget.Tools_Entry);
      Attach (Table, Widget.Tools_Entry, 1, 2, 1, 2);
      Set_Tip
        (Tips, Widget.Tools_Entry,
         -("This path will be used to spawn all actions not related to code" &
           " generation. These actions are (the list is not exclusive)" &
           " gnatcheck, gnatmetrics, cross-reference generation."));

      for J in 1 .. 2 loop
         Gtk_New (Browse);
         Gtk_New (Pix, Stock_Open, Icon_Size_Menu);
         Add (Browse, Pix);
         Set_Relief (Browse, Relief_None);
         Set_Border_Width (Browse, 0);
         Unset_Flags (Browse, Can_Focus or Can_Default);
         Show_All (Browse);
         Attach (Table, Browse, 2, 3, Guint (J - 1), Guint (J));
         Set_Tip
           (Tips, Browse,
            -"Use this button to select the folder with a file explorer");

         if J = 1 then
            Entry_Callback.Connect
              (Browse, Signal_Clicked,
               On_Browse'Access,
               (The_Entry => Widget.Compiler_Entry,
                Dialog    => Widget));
         else
            Entry_Callback.Connect
              (Browse, Signal_Clicked,
               On_Browse'Access,
               (The_Entry => Widget.Compiler_Entry,
                Dialog    => Widget));
         end if;
      end loop;

      Gtk_New
        (Check,
         -"Use the compiler in tools path to generate cross-reference files");
      Show_All (Check);
      Set_Active (Check, Widget.Xrefs_Subdir);
      Attach (Table, Check, 0, 2, 2, 3);
      Set_Tip
        (Tips, Check,
         -("If checked, then GPS will create a new Build target for " &
           "automatically generating cross reference files using the " &
           "compiler found in the tools path. Those cross reference files " &
           "are placed in a specific subdirectory, so will not interract " &
           "with object and cross reference files generated by the " &
           "regular compiler used for actually building the project." &
           ASCII.LF & ASCII.LF &
           "This functionnality is mainly used to allow full GPS " &
           "functionalities with old compilers. If you need to use an old " &
           "compiler with your project, then you might consider using this " &
           "feature."));
      Dualc_Callback.Connect
        (Check, Signal_Toggled, Xrefs_Toggled'Access, Widget);

   end Gtk_New;

   ----------------
   -- Get_Active --
   ----------------

   function Get_Active
     (Widget : access Dualc_Dialog_Record'Class) return Boolean
   is
   begin
      return Widget.Active;
   end Get_Active;

   --------------------------
   -- Get_Use_Xrefs_Subdir --
   --------------------------

   function Get_Use_Xrefs_Subdir
     (Widget : access Dualc_Dialog_Record'Class) return Boolean
   is
   begin
      return Widget.Xrefs_Subdir;
   end Get_Use_Xrefs_Subdir;

   --------------------
   -- Get_Tools_Path --
   --------------------

   function Get_Tools_Path
     (Widget : access Dualc_Dialog_Record'Class) return String is
   begin
      return Get_Text (Widget.Tools_Entry);
   end Get_Tools_Path;

   -----------------------
   -- Get_Compiler_Path --
   -----------------------

   function Get_Compiler_Path
     (Widget : access Dualc_Dialog_Record'Class) return String is
   begin
      return Get_Text (Widget.Compiler_Entry);
   end Get_Compiler_Path;

end Dualcompilation_Dialog;
