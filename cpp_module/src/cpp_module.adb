-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2002-2004                       --
--                            ACT-Europe                             --
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

with Glide_Kernel;             use Glide_Kernel;
with Glide_Kernel.Console;     use Glide_Kernel.Console;
with Glide_Kernel.Project;     use Glide_Kernel.Project;
with Language_Handlers.Glide;  use Language_Handlers.Glide;
with Language.C;               use Language.C;
with Language.Cpp;             use Language.Cpp;
with Entities;                 use Entities;
with CPP_Parser;               use CPP_Parser;
with Traces;                   use Traces;
with Ada.Exceptions;           use Ada.Exceptions;
with Ada.Unchecked_Deallocation;
with Glide_Intl;               use Glide_Intl;
with Projects;                 use Projects;
with Projects.Registry;        use Projects.Registry;
with Ada.Exceptions;           use Ada.Exceptions;
with Glib.Properties.Creation; use Glib, Glib.Properties.Creation;
with Glide_Intl;               use Glide_Intl;
with Glide_Kernel.Hooks;       use Glide_Kernel.Hooks;
with Glide_Kernel.Preferences; use Glide_Kernel.Preferences;
with Language;                 use Language;
with Project_Viewers;          use Project_Viewers;
with Naming_Editors;           use Naming_Editors;
with Foreign_Naming_Editors;   use Foreign_Naming_Editors;
with Case_Handling;            use Case_Handling;

package body Cpp_Module is

   CPP_LI_Handler_Name : constant String := "c/c++";
   --  The name the source navigator is registered under.

   C_Automatic_Indentation   : Param_Spec_Enum;
   C_Use_Tabs                : Param_Spec_Boolean;
   C_Indentation_Level       : Param_Spec_Int;

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (LI_Handler_Record'Class, LI_Handler);

   procedure Project_View_Changed
     (Kernel : access Kernel_Handle_Record'Class);
   --  Called when the project view has changed in the kernel.
   --  This resets the internal data for the C/C++ handler.

   procedure On_Preferences_Changed
     (Kernel : access Kernel_Handle_Record'Class);
   --  Called when the preferences have changed

   function C_Naming_Scheme_Editor
     (Kernel : access Kernel_Handle_Record'Class; Lang : String)
      return Language_Naming_Editor;
   --  Create the naming scheme editor page

   ----------------------------
   -- C_Naming_Scheme_Editor --
   ----------------------------

   function C_Naming_Scheme_Editor
     (Kernel : access Kernel_Handle_Record'Class; Lang : String)
      return Language_Naming_Editor
   is
      pragma Unreferenced (Kernel);
      Naming : Foreign_Naming_Editor;
   begin
      Gtk_New (Naming, Lang);
      return Language_Naming_Editor (Naming);
   end C_Naming_Scheme_Editor;

   ----------------------------
   -- On_Preferences_Changed --
   ----------------------------

   procedure On_Preferences_Changed
     (Kernel : access Kernel_Handle_Record'Class)
   is
      Style  : constant Indentation_Kind := Indentation_Kind'Val
        (Get_Pref (Kernel, C_Automatic_Indentation));
      Tabs   : constant Boolean := Get_Pref (Kernel, C_Use_Tabs);
      Params : constant Indent_Parameters :=
                 (Indent_Level        =>
                    Integer (Get_Pref (Kernel, C_Indentation_Level)),
                  Indent_Continue     => 0,
                  Indent_Decl         => 0,
                  Tab_Width           =>
                    Integer (Get_Pref (Kernel, Tab_Width)),
                  Indent_Case_Extra   => Automatic,
                  Reserved_Casing     => Case_Handling.Unchanged,
                  Ident_Casing        => Case_Handling.Unchanged,
                  Format_Operators    => False,
                  Use_Tabs            => Tabs,
                  Align_On_Colons     => False,
                  Align_On_Arrows     => False,
                  Align_Decl_On_Colon => False);

   begin
      Set_Indentation_Parameters
        (C_Lang,
         Indent_Style  => Style,
         Params        => Params);
      Set_Indentation_Parameters
        (Cpp_Lang,
         Indent_Style  => Style,
         Params        => Params);
   end On_Preferences_Changed;

   --------------------------
   -- Project_View_Changed --
   --------------------------

   procedure Project_View_Changed
     (Kernel : access Kernel_Handle_Record'Class)
   is
      Handler : constant Glide_Language_Handler := Glide_Language_Handler
        (Get_Language_Handler (Kernel));
   begin
      if Object_Path (Get_Project (Kernel), False) = "" then
         Insert (Kernel,
                 -("The root project must have an object directory set, or"
                   & " C/C++ browsing is disabled"), Mode => Error);
      end if;

      CPP_Parser.On_Project_View_Changed
        (Get_LI_Handler_By_Name (Handler, CPP_LI_Handler_Name));

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end Project_View_Changed;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
   is
      Handler : constant Glide_Language_Handler := Glide_Language_Handler
        (Get_Language_Handler (Kernel));
      LI      : LI_Handler := Create_CPP_Handler
        (Get_Database (Kernel), Project_Registry (Get_Registry (Kernel)));
      Msg     : constant String := Set_Executables (LI);

   begin
      if Msg /= "" then
         --  No parser will be available. However, we still want the
         --  highlighting for C and C++ files

         Insert (Kernel, Msg, Mode => Error);
         Unchecked_Free (LI);
      else
         Add_Hook
           (Kernel, Project_View_Changed_Hook, Project_View_Changed'Access);
      end if;

      On_Project_View_Changed (LI);
      Register_LI_Handler (Handler, CPP_LI_Handler_Name, LI);

      Register_Language (Handler, "c", C_Lang);
      Set_Language_Handler
        (Handler, "c",
         LI                  => LI);
      Register_Default_Language_Extension
        (Get_Registry (Kernel),
         Language_Name       => "c",
         Default_Spec_Suffix => ".h",
         Default_Body_Suffix => ".c");

      Register_Language (Handler, "c++", Cpp_Lang);
      Set_Language_Handler
        (Handler, "c++",
         LI                  => LI);
      Register_Default_Language_Extension
        (Get_Registry (Kernel),
         Language_Name       => "c++",
         Default_Spec_Suffix => ".hh",
         Default_Body_Suffix => ".cpp");

      C_Automatic_Indentation := Param_Spec_Enum
        (Indentation_Properties.Gnew_Enum
           (Name    => "C-Auto-Indentation",
            Default => Extended,
            Blurb   => -"How the editor should indent C/C++ sources",
            Nick    => -"Auto indentation"));
      Register_Property
        (Kernel, Param_Spec (C_Automatic_Indentation), -"Editor:C/C++");

      C_Use_Tabs := Param_Spec_Boolean
        (Gnew_Boolean
          (Name    => "C-Use-Tabs",
           Default => True,
           Blurb   =>
             -("Whether the editor should use tabulations when indenting"),
           Nick    => -"Use tabulations"));
      Register_Property
        (Kernel, Param_Spec (C_Use_Tabs), -"Editor:C/C++");

      C_Indentation_Level := Param_Spec_Int
        (Gnew_Int
          (Name    => "C-Indent-Level",
           Minimum => 1,
           Maximum => 9,
           Default => 2,
           Blurb   => -"The number of spaces for the default indentation",
           Nick    => -"Default indentation"));
      Register_Property
        (Kernel, Param_Spec (C_Indentation_Level), -"Editor:C/C++");

      Add_Hook
        (Kernel, Preferences_Changed_Hook, On_Preferences_Changed'Access);
      On_Preferences_Changed (Kernel);

      Register_Naming_Scheme_Editor
        (Kernel, C_String, C_Naming_Scheme_Editor'Access);
      Register_Naming_Scheme_Editor
        (Kernel, Cpp_String, C_Naming_Scheme_Editor'Access);

   exception
      when E : others =>
         Trace (Exception_Handle, "Unexpected exception in Register_Module: "
                & Exception_Information (E));
   end Register_Module;

end Cpp_Module;
