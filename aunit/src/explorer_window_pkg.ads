------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                           Explorer_Window_Pkg                            --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                            $Revision$
--                                                                          --
--                Copyright (C) 2001 Ada Core Technologies, Inc.            --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the Free Software Foundation,  59 Temple Place - Suite 330,  Boston, --
-- MA 02111-1307, USA.                                                      --
--                                                                          --
-- GNAT is maintained by Ada Core Technologies Inc (http://www.gnat.com).   --
--                                                                          --
------------------------------------------------------------------------------

with Gtk.Window; use Gtk.Window;
with Gtk.Box; use Gtk.Box;
with Gtk.Scrolled_Window; use Gtk.Scrolled_Window;
with Gtk.Clist; use Gtk.Clist;
with Gtk.Label; use Gtk.Label;
with Gtk.Hbutton_Box; use Gtk.Hbutton_Box;
with Gtk.Button; use Gtk.Button;
with GNAT.OS_Lib; use GNAT.OS_Lib;

package Explorer_Window_Pkg is

   type Explorer_Window_Record is new Gtk_Window_Record with record
      Directory : String_Access;
      Harness_Window : Gtk_Window;

      --
      Vbox7 : Gtk_Vbox;
      Scrolledwindow1 : Gtk_Scrolled_Window;
      Clist : Gtk_Clist;
      Label4 : Gtk_Label;
      Label5 : Gtk_Label;
      Hbuttonbox2 : Gtk_Hbutton_Box;
      Ok : Gtk_Button;
      Cancel : Gtk_Button;
   end record;
   type Explorer_Window_Access is access all Explorer_Window_Record'Class;

   procedure Gtk_New (Explorer_Window : out Explorer_Window_Access);
   procedure Initialize
     (Explorer_Window : access Explorer_Window_Record'Class);

   procedure Fill (Explorer_Window : Explorer_Window_Access);
   --  Fill the list with the files in the directory.
   --  Files are annotated with their AUnit kind (test_suite, test_case)

end Explorer_Window_Pkg;
