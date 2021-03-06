------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                       Copyright (C) 2016-2018, AdaCore                   --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------
--  Main entry point for GNAThub module

with GPS.Kernel.Modules;
with GPS.Kernel.MDI;             use GPS.Kernel.MDI;

with GNAThub.Filters;
with GNAThub.Reports.Collector;
limited with GNAThub.Loader;

package GNAThub.Module is

   type Filter_Access is access all GNAThub.Filters.Message_Filter'Class;

   type Loader_Access is access all GNAThub.Loader.Loader'Class;

   type GNAThub_Child_Record is new GPS_MDI_Child_Record with null record;
   type GNAThub_Child is access all GNAThub_Child_Record'Class;

   type GNAThub_Module_Id_Record is
     new GPS.Kernel.Modules.Module_ID_Record with record
      Kernel        : GPS.Kernel.Kernel_Handle;
      Tools         : Tools_Ordered_Sets.Set;
      Severities    : Severities_Ordered_Sets.Set;
      Severities_Id : Severity_Natural_Maps.Map;
      Rules         : Rule_Sets.Set;
      Filter        : Filter_Access;
      Loader        : Loader_Access;

      Tree          : Code_Analysis.Code_Analysis_Tree;
      Collector     : GNAThub.Reports.Collector.Report;
      Report        : GNAThub_Child;
   end record;

   type GNAThub_Module_Id is access all GNAThub_Module_Id_Record'Class;

   procedure Display_Data (Self : in out GNAThub_Module_Id_Record'Class);
   --  Loads and displays analysis data. Doesn't run GNAThub, reports error
   --  when database is not exists.

   procedure Clean (Self : in out GNAThub_Module_Id_Record'Class);
   --  Deallocate all loaded data

   procedure Update_Report (Self : in out GNAThub_Module_Id_Record'Class);
   --  Called when preferences or filter criterias for report have been changed

   function New_Severity
     (Self       : in out GNAThub_Module_Id_Record'Class;
      Severity   : Severity_Enum)
      return Severity_Access;
   --  Creates new severity object

   function New_Tool
     (Self : in out GNAThub_Module_Id_Record'Class;
      Name : Ada.Strings.Unbounded.Unbounded_String) return Tool_Access;
   --  Creates new tool object

   function New_Rule
     (Self       : in out GNAThub_Module_Id_Record'Class;
      Tool       : not null Tool_Access;
      Name       : Ada.Strings.Unbounded.Unbounded_String;
      Identifier : Ada.Strings.Unbounded.Unbounded_String)
      return Rule_Access;
   --  Creates new rule object for tool

   procedure Register_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class);
   --  Registers module.

end GNAThub.Module;
