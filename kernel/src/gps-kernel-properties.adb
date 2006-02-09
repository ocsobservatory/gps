-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2005-2006                       --
--                              AdaCore                              --
--                                                                   --
-- GPS is free  software; you  can redistribute it and/or modify  it --
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

with Ada.Unchecked_Deallocation;
with File_Utils;                 use File_Utils;
with GNAT.OS_Lib;                use GNAT.OS_Lib;
with GPS.Intl;                   use GPS.Intl;
with GPS.Kernel.Scripts;         use GPS.Kernel.Scripts;
with Glib.Xml_Int;               use Glib.Xml_Int;
with Projects;                   use Projects;
with String_Hash;
with Traces;                     use Traces;
with VFS;                        use VFS;

package body GPS.Kernel.Properties is
   Me : constant Debug_Handle := Create ("Properties");

   type Property_Description is record
      Value      : Property_Access;
      --  The actual value of the property. This is still null if the property
      --  hasn't been parsed yet (and then Unparsed it not null and contains
      --  the value read from the XML file). This parsing is implemented
      --  lazily so that we do not have to register the property types in
      --  advance, and they are only needed when actually reading a property

      Unparsed   : Node_Ptr;
      Persistent : Boolean;
   end record;
   type Property_Description_Access is access Property_Description;
   --  The description of a property

   procedure Free (Description : in out Property_Description_Access);

   package Properties_Description_Hash is new String_Hash
     (Data_Type      => Property_Description_Access,
      Free_Data      => Free,
      Null_Ptr       => null,
      Case_Sensitive => True);
   use Properties_Description_Hash.String_Hash_Table;

   type Properties_Description_HTable is
     access all Properties_Description_Hash.String_Hash_Table.HTable;

   procedure Free (Hash : in out Properties_Description_HTable);

   package Properties_Hash is new String_Hash
     (Data_Type      => Properties_Description_HTable,
      Free_Data      => Free,
      Null_Ptr       => null,
      Case_Sensitive => Filenames_Are_Case_Sensitive);
   use Properties_Hash.String_Hash_Table;

   All_Properties : Properties_Hash.String_Hash_Table.HTable;
   --  Global variable storing all the current properties for the current
   --  project.
   --  ??? It would be nicer to store this in the kernel but:
   --    - it really doesn't provide anything in addition (no more task safe
   --      in any case)
   --    - It would require an extra Kernel parameter to Set_Property
   --      and Get_Property, thus making the API harder to use.
   --  For now, we'll leave with this global variable.

   function Get_Properties_Filename
     (Kernel : access Kernel_Handle_Record'Class) return String;
   --  Return the filename to use when saving the persistent properties for the
   --  current project

   procedure Set_Resource_Property
     (Resource_Key  : String;
      Resource_Kind : String;
      Name          : String;
      Property      : Property_Description);
   --  Set property for any kind of resource. This is the internal
   --  implementation of Set_*_Property

   procedure Get_Resource_Property
     (Property      : out Property_Record'Class;
      Resource_Key  : String;
      Resource_Kind : String;
      Name          : String;
      Found         : out Boolean);
   --  Get property for any kind of resource

   procedure Remove_Resource_Property
     (Resource_Key  : String;
      Resource_Kind : String;
      Name          : String);
   --  Remove property for any kind of resource

   procedure File_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handles script commands for properties

   procedure Project_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handles script commands for properties

   procedure Properties_Command_Handler
     (Data : in out Callback_Data'Class; Command : String);
   --  Handles script commands for properties

   ----------
   -- Free --
   ----------

   procedure Free (Description : in out Property_Description_Access) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Property_Record'Class, Property_Access);
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Property_Description, Property_Description_Access);
   begin
      if Description.Value /= null then
         Destroy (Description.Value.all);
         Unchecked_Free (Description.Value);
      end if;
      if Description.Unparsed /= null then
         Free (Description.Unparsed);
      end if;
      Unchecked_Free (Description);
   end Free;

   ----------
   -- Free --
   ----------

   procedure Free (Hash : in out Properties_Description_HTable) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Properties_Description_Hash.String_Hash_Table.HTable,
         Properties_Description_HTable);
   begin
      if Hash /= null then
         Reset (Hash.all);
         Unchecked_Free (Hash);
      end if;
   end Free;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Property : in out Property_Record) is
      pragma Unreferenced (Property);
   begin
      null;
   end Destroy;

   ----------
   -- Save --
   ----------

   procedure Save
     (Property : access String_Property;
      Node     : in out Glib.Xml_Int.Node_Ptr) is
   begin
      if Property.Value /= null then
         Node.Value := new String'(Property.Value.all);
      end if;
   end Save;

   ----------
   -- Save --
   ----------

   procedure Save
     (Property : access Integer_Property;
      Node     : in out Glib.Xml_Int.Node_Ptr) is
   begin
      Node.Value := new String'(Integer'Image (Property.Value));
   end Save;

   ----------
   -- Save --
   ----------

   procedure Save
     (Property : access Boolean_Property;
      Node     : in out Glib.Xml_Int.Node_Ptr) is
   begin
      Node.Value := new String'(Boolean'Image (Property.Value));
   end Save;

   ----------
   -- Load --
   ----------

   procedure Load
     (Property : in out String_Property; From : Glib.Xml_Int.Node_Ptr) is
   begin
      if From.Value /= null then
         Property.Value := new String'(From.Value.all);
      else
         Property.Value := null;
      end if;
   end Load;

   ----------
   -- Load --
   ----------

   procedure Load
     (Property : in out Integer_Property; From : Glib.Xml_Int.Node_Ptr) is
   begin
      Property.Value := Integer'Value (From.Value.all);
   exception
      when Constraint_Error =>
         Property.Value := 0;
   end Load;

   ----------
   -- Load --
   ----------

   procedure Load
     (Property : in out Boolean_Property; From : Glib.Xml_Int.Node_Ptr) is
   begin
      Property.Value := Boolean'Value (From.Value.all);
   exception
      when Constraint_Error =>
         Property.Value := True;
   end Load;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Property : in out String_Property) is
   begin
      Free (Property.Value);
   end Destroy;

   ---------------------------
   -- Set_Resource_Property --
   ---------------------------

   procedure Set_Resource_Property
     (Resource_Key  : String;
      Resource_Kind : String;
      Name          : String;
      Property      : Property_Description)
   is
      pragma Unreferenced (Resource_Kind);
      --  Not used yet, the idea is to have various attributes in the XML file
      --  depending on the resource type

      Hash : Properties_Description_HTable;
   begin
      Hash := Get (All_Properties, Resource_Key);
      if Hash = null then
         Hash := new Properties_Description_Hash.String_Hash_Table.HTable;
         Set (All_Properties, Resource_Key, Hash);
      end if;

      Set (Hash.all, Name, new Property_Description'(Property));
   end Set_Resource_Property;

   ---------------------------
   -- Get_Resource_Property --
   ---------------------------

   procedure Get_Resource_Property
     (Property      : out Property_Record'Class;
      Resource_Key  : String;
      Resource_Kind : String;
      Name          : String;
      Found         : out Boolean)
   is
      pragma Unreferenced (Resource_Kind);
      Hash : Properties_Description_HTable;
      Descr : Property_Description_Access;
   begin
      Found := False;
      Hash := Get (All_Properties, Resource_Key);
      if Hash /= null then
         Descr := Get (Hash.all, Name);
         if Descr /= null then
            if Descr.Value = null then
               Load (Property, Descr.Unparsed);
               Descr.Value := new Property_Record'Class'(Property);
               Free (Descr.Unparsed);  --  No longer needed
            end if;

            Property := Descr.Value.all;
            Found := True;
         end if;
      end if;

   exception
      when others =>
         Found := False;
   end Get_Resource_Property;

   ------------------------------
   -- Remove_Resource_Property --
   ------------------------------

   procedure Remove_Resource_Property
     (Resource_Key  : String;
      Resource_Kind : String;
      Name          : String)
   is
      pragma Unreferenced (Resource_Kind);
      Hash : Properties_Description_HTable;
   begin
      Hash := Get (All_Properties, Resource_Key);
      if Hash /= null then
         Remove (Hash.all, Name);
      end if;
   end Remove_Resource_Property;

   ------------------
   -- Set_Property --
   ------------------

   procedure Set_Property
     (File       : VFS.Virtual_File;
      Name       : String;
      Property   : access Property_Record'Class;
      Persistent : Boolean := False) is
   begin
      Set_Resource_Property
        (Full_Name (File).all, "file", Name,
         Property_Description'(Value      => Property_Access (Property),
                               Unparsed   => null,
                               Persistent => Persistent));
   end Set_Property;

   ------------------
   -- Set_Property --
   ------------------

   procedure Set_Property
     (Project    : Projects.Project_Type;
      Name       : String;
      Property   : access Property_Record'Class;
      Persistent : Boolean := False) is
   begin
      Set_Resource_Property
        (Full_Name (Project_Path (Project)).all, "project", Name,
         Property_Description'(Value      => Property_Access (Property),
                               Unparsed   => null,
                               Persistent => Persistent));
   end Set_Property;

   ------------------
   -- Get_Property --
   ------------------

   procedure Get_Property
     (Property : out Property_Record'Class;
      File     : VFS.Virtual_File;
      Name     : String;
      Found    : out Boolean) is
   begin
      Get_Resource_Property
        (Property, Full_Name (File).all, "file", Name, Found);
   end Get_Property;

   ------------------
   -- Get_Property --
   ------------------

   procedure Get_Property
     (Property : out Property_Record'Class;
      Project  : Projects.Project_Type;
      Name     : String;
      Found    : out Boolean) is
   begin
      Get_Resource_Property
        (Property, Full_Name (Project_Path (Project)).all,
         "project", Name, Found);
   end Get_Property;

   ---------------------
   -- Remove_Property --
   ---------------------

   procedure Remove_Property
     (File     : VFS.Virtual_File;
      Name     : String) is
   begin
      Remove_Resource_Property (Full_Name (File).all, "file", Name);
   end Remove_Property;

   ---------------------
   -- Remove_Property --
   ---------------------

   procedure Remove_Property
     (Project  : Projects.Project_Type;
      Name     : String) is
   begin
      Remove_Resource_Property
        (Full_Name (Project_Path (Project)).all, "project", Name);
   end Remove_Property;

   -----------------------------
   -- Get_Properties_Filename --
   -----------------------------

   function Get_Properties_Filename
     (Kernel : access Kernel_Handle_Record'Class) return String is
   begin
      --  We could use the .gps directory, but that would mean we have to keep
      --  in memory information for files that do not belong to the current
      --  project.

      return Get_Home_Dir (Kernel) & "properties.xml";
   end Get_Properties_Filename;

   --------------------------------
   -- Save_Persistent_Properties --
   --------------------------------

   procedure Save_Persistent_Properties
     (Kernel : access Kernel_Handle_Record'Class)
   is
      Filename : constant String := Get_Properties_Filename (Kernel);
      Iter  : Properties_Hash.String_Hash_Table.Iterator;
      Iter2 : Properties_Description_Hash.String_Hash_Table.Iterator;
      Hash  : Properties_Description_HTable;
      Root, File, Prop : Node_Ptr;
      Descr : Property_Description_Access;
   begin
      Trace (Me, "Saving " & Filename);
      Root := new Node'
        (Tag        => new String'("persistent_properties"),
         Attributes => null,
         Value      => null,
         Parent     => null,
         Child      => null,
         Next       => null,
         Specific_Data => 1);

      Get_First (All_Properties, Iter);
      loop
         Hash := Get_Element (Iter);
         exit when Hash = null;

         File := new Node'
           (Tag        => new String'("properties"),
            Attributes => new String'("file='" & Get_Key (Iter) & "'"),
            Value      => null,
            Parent     => null,
            Child      => null,
            Next       => null,
            Specific_Data => 1);

         Get_First (Hash.all, Iter2);
         loop
            Descr := Get_Element (Iter2);
            exit when Descr = null;

            if Descr.Persistent then
               if Descr.Value = null then
                  Descr.Unparsed.Tag := new String'("property");
                  Prop := Descr.Unparsed;
                  Descr.Unparsed := null;

               else
                  Prop := new Node'
                    (Tag        => new String'("property"),
                     Attributes =>
                        new String'("name='" & Get_Key (Iter2) & "'"),
                     Value      => null,
                     Parent     => null,
                     Child      => null,
                     Next       => null,
                     Specific_Data => 1);
                  Save (Descr.Value, Prop);
               end if;
               if Prop /= null then
                  Add_Child (File, Prop);
               end if;
            end if;

            Get_Next (Hash.all, Iter2);
         end loop;

         if File.Child /= null then
            Add_Child (Root, File);
         else
            Free (File);
         end if;

         Get_Next (All_Properties, Iter);
      end loop;

      Print (Root, Filename);
      Free (Root);
   end Save_Persistent_Properties;

   ----------------------
   -- Reset_Properties --
   ----------------------

   procedure Reset_Properties
     (Kernel : access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Kernel);
   begin
      Reset (All_Properties);
   end Reset_Properties;

   -----------------------------------
   -- Restore_Persistent_Properties --
   -----------------------------------

   procedure Restore_Persistent_Properties
     (Kernel : access Kernel_Handle_Record'Class)
   is
      Filename : constant String := Get_Properties_Filename (Kernel);
      Root, File, Prop, Prop2 : Node_Ptr;
   begin
      Trace (Me, "Loading " & Filename);
      if Is_Readable_File (Filename) then
         Root := Parse (Filename);
         if Root /= null then
            File := Root.Child;
         end if;
         while File /= null loop
            Prop := File.Child;
            while Prop /= null loop
               Prop2 := Deep_Copy (Prop);
               Xml_Int.Free (Prop2.Tag);
               --  Prop.Tag is not needed, always "property", and this
               --  saves space in memory

               Set_Resource_Property
                 (Resource_Key  => Get_Attribute (File, "file"),
                  Resource_Kind => "file",
                  Name          => Get_Attribute (Prop, "name"),
                  Property      => (Value      => null,
                                    Unparsed   => Prop2,
                                    Persistent => True));
               Prop := Prop.Next;
            end loop;

            File := File.Next;
         end loop;
         Free (Root);
      end if;
   end Restore_Persistent_Properties;

   --------------------------
   -- File_Command_Handler --
   --------------------------

   procedure File_Command_Handler
     (Data : in out Callback_Data'Class; Command : String)
   is
      Kernel     : constant Kernel_Handle := Get_Kernel (Data);
      File_Class : constant Class_Type := New_Class (Kernel, "File");
      Inst       : constant Class_Instance := Nth_Arg (Data, 1, File_Class);
      File       : constant Virtual_File := Get_Data (Inst);

      Name       : aliased constant String := "name";
      Value      : aliased constant String := "value";
      Persistent : aliased constant String := "persistent";

      Found      : Boolean;
      Prop       : String_Property_Access;
      Prop2      : aliased String_Property;
   begin
      if Command = "set_property" then
         Name_Parameters (Data, (2 => Name'Unchecked_Access,
                                 3 => Value'Unchecked_Access,
                                 4 => Persistent'Unchecked_Access));
         Prop := new String_Property'(Value => new String'(Nth_Arg (Data, 3)));
         Set_Property
           (File,
            Name       => Nth_Arg (Data, 2),
            Property   => Prop,
            Persistent => Nth_Arg (Data, 4, False));
      elsif Command = "get_property" then
         Name_Parameters (Data, (2 => Name'Unchecked_Access));
         Get_Property
           (Property => Prop2,
            File     => File,
            Name     => Nth_Arg (Data, 2),
            Found    => Found);
         if not Found then
            Set_Error_Msg (Data, -"Property not found");
         elsif Prop2.Value = null then
            Set_Return_Value (Data, "");
         else
            Set_Return_Value (Data, Prop2.Value.all);
         end if;

      else
         Name_Parameters (Data, (2 => Name'Unchecked_Access));
         Remove_Property
           (File     => File,
            Name     => Nth_Arg (Data, 2));
      end if;
   end File_Command_Handler;

   -----------------------------
   -- Project_Command_Handler --
   -----------------------------

   procedure Project_Command_Handler
     (Data : in out Callback_Data'Class; Command : String)
   is
      Project    : constant Project_Type  := Get_Data (Data, 1);

      Name       : aliased constant String := "name";
      Value      : aliased constant String := "value";
      Persistent : aliased constant String := "persistent";

      Found      : Boolean;
      Prop       : String_Property_Access;
      Prop2      : aliased String_Property;
   begin
      if Command = "set_property" then
         Name_Parameters (Data, (2 => Name'Unchecked_Access,
                                 3 => Value'Unchecked_Access,
                                 4 => Persistent'Unchecked_Access));
         Prop := new String_Property'(Value => new String'(Nth_Arg (Data, 3)));
         Set_Property
           (Project,
            Name       => Nth_Arg (Data, 2),
            Property   => Prop,
            Persistent => Nth_Arg (Data, 4, False));
      elsif Command = "get_property" then
         Name_Parameters (Data, (2 => Name'Unchecked_Access));
         Get_Property
           (Property => Prop2,
            Project     => Project,
            Name     => Nth_Arg (Data, 2),
            Found    => Found);
         if not Found then
            Set_Error_Msg (Data, -"Property not found");
         elsif Prop2.Value = null then
            Set_Return_Value (Data, "");
         else
            Set_Return_Value (Data, Prop2.Value.all);
         end if;

      else
         Name_Parameters (Data, (2 => Name'Unchecked_Access));
         Remove_Property
           (Project  => Project,
            Name     => Nth_Arg (Data, 2));
      end if;
   end Project_Command_Handler;

   --------------------------------
   -- Properties_Command_Handler --
   --------------------------------

   procedure Properties_Command_Handler
     (Data : in out Callback_Data'Class; Command : String) is
   begin
      if Command = "save_persistent_properties" then
         Save_Persistent_Properties (Get_Kernel (Data));
      end if;
   end Properties_Command_Handler;

   ------------------------------
   -- Register_Script_Commands --
   ------------------------------

   procedure Register_Script_Commands
     (Kernel : access Kernel_Handle_Record'Class)
   is
      File_Class : constant Class_Type := New_Class (Kernel, "File");
      Project_Class : constant Class_Type := New_Class (Kernel, "Project");
   begin
      Register_Command
        (Kernel, "set_property",
         Minimum_Args => 2,
         Maximum_Args => 3,
         Class        => File_Class,
         Handler      => File_Command_Handler'Access);
      Register_Command
        (Kernel, "get_property",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class        => File_Class,
         Handler      => File_Command_Handler'Access);
      Register_Command
        (Kernel, "remove_property",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class        => File_Class,
         Handler      => File_Command_Handler'Access);

      Register_Command
        (Kernel, "set_property",
         Minimum_Args => 2,
         Maximum_Args => 3,
         Class        => Project_Class,
         Handler      => Project_Command_Handler'Access);
      Register_Command
        (Kernel, "get_property",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class        => Project_Class,
         Handler      => Project_Command_Handler'Access);
      Register_Command
        (Kernel, "remove_property",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class        => Project_Class,
         Handler      => Project_Command_Handler'Access);

      Register_Command
        (Kernel, "save_persistent_properties",
         Handler => Properties_Command_Handler'Access);
   end Register_Script_Commands;

end GPS.Kernel.Properties;
