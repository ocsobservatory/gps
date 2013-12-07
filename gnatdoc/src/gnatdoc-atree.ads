------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2007-2013, AdaCore                     --
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

--  This package defines the format of the tree used to represent the sources
--  internally. Semantic information and documentation retrieved from sources
--  are combined in this tree. There is no separate symbol table structure.

--  Each tree nodes is composed of two parts:

--    * Low level: This part contains the information retrieved directly from
--      the Xref database. This information should be fully reliable since it
--      is the information in the Sqlite database which is composed of the
--      information directly retrieved from the LI files generated by the
--      compiler. By contrast in some cases this information may not be
--      complete enough to have the full context of a given entity. The
--      low level information of a node is available through the routines
--      of package LL.

--    * High Level: This part complements the low level information. It is
--      composed of information synthesized from combinations of low level
--      attributes and information synthesized using the context of an
--      entity by the frontend of GNATdoc. The high level information of a
--      node is directly available through the public routines of this
--      package (excluding the routines of package LL).

with Ada.Containers.Vectors;
with GNATCOLL.Symbols;        use GNATCOLL.Symbols;
with Language;                use Language;
with GNATdoc.Comment;         use GNATdoc.Comment;
with Xref.Docgen;             use Xref.Docgen;

private package GNATdoc.Atree is
   Std_Entity_Name : constant String := "Standard";

   type Entity_Info_Record is private;
   type Entity_Id is access all Entity_Info_Record;
   No_Entity : constant Entity_Id := null;

   procedure Initialize;
   --  Initialize internal state used to associate unique identifiers to all
   --  the tree nodes.

   function No (E : Entity_Id) return Boolean;
   --  Return true if E is null

   function Present (E : Entity_Id) return Boolean;
   --  Return true if E is not null

   -----------------
   -- Entity_Info --
   -----------------

   type Entity_Kind is
     (E_Unknown,
      E_Abstract_Function,
      E_Abstract_Procedure,
      E_Abstract_Record_Type,
      E_Access_Type,
      E_Array_Type,
      E_Boolean_Type,
      E_Class_Wide_Type,
      E_Decimal_Fixed_Point_Type,
      E_Entry,
      E_Enumeration_Type,
      E_Enumeration_Literal,
      E_Exception,
      E_Fixed_Point_Type,
      E_Floating_Point_Type,
      E_Function,
      E_Generic_Function,
      E_Generic_Package,
      E_Generic_Procedure,
      E_Interface,
      E_Integer_Type,
      E_Named_Number,
      E_Package,
      E_Private_Object,
      E_Procedure,
      E_Protected_Type,
      E_Record_Type,
      E_Single_Protected,
      E_Single_Task,
      E_String_Type,
      E_Task_Type,
      E_Variable,

      --  Synthesized Ada values

      E_Access_Subprogram_Type,
      E_Discriminant,
      E_Component,
      E_Formal,
      E_Generic_Formal,
      E_Tagged_Record_Type,

      --  C/C++
      E_Macro,
      E_Function_Macro,
      E_Class,
      E_Class_Instance,
      E_Include_File,

      --  Synthesized C++ values

      E_Attribute);

   ----------------
   -- EInfo_List --
   ----------------

   package EInfo_List is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Entity_Id);
   procedure Free (List : in out EInfo_List.Vector);

   function Less_Than_Loc (Left, Right : Entity_Id) return Boolean;
   --  Compare by location. When two entities are defined in different files
   --  instead of returning False we extend the meaning of the comparison and
   --  compare them using the base name of their files. Done to avoid spurious
   --  output differences between continuous builders.

   package EInfo_Vector_Sort_Loc is new EInfo_List.Generic_Sorting
     ("<" => Less_Than_Loc);

   function Less_Than_Short_Name (Left, Right : Entity_Id) return Boolean;
   --  Compare by name. When two entities have the same name (for example,
   --  overloaded subprograms) instead of returning False we extend the
   --  meaning of the comparison and compare them using their location.
   --  Done to avoid spurious output differences between continuous builders.

   package EInfo_Vector_Sort_Short is new EInfo_List.Generic_Sorting
     ("<" => Less_Than_Short_Name);

   function Less_Than_Full_Name (Left, Right : Entity_Id) return Boolean;
   package EInfo_Vector_Sort_Full is new EInfo_List.Generic_Sorting
     ("<" => Less_Than_Full_Name);

   procedure Append_Unique_Elmt
     (Container : in out EInfo_List.Vector;
      Entity    : Entity_Id);
   --  Append Entity to the Container only if the container has no entity
   --  whose location matches the location of Entity.

   procedure Delete_Entity
     (List   : in out EInfo_List.Vector;
      Entity : General_Entity);
   procedure Delete_Entity
     (List   : in out EInfo_List.Vector;
      Entity : Entity_Id);
   --  Raise Not_Found if Entity is not found in List

   function Find_Entity
     (List   : EInfo_List.Vector;
      Entity : General_Entity) return Entity_Id;
   function Find_Entity
     (List : EInfo_List.Vector;
      Name : String) return Entity_Id;
   --  Find the entity with Name in List. Name may be a short name or an
   --  expanded name. If not found then return No_Entity.

   procedure For_All
     (Vector  : in out EInfo_List.Vector;
      Process : access procedure (E_Info : Entity_Id));
   --  Call subprogram Process for all the elements of Vector

   function Has_Duplicated_Entities
     (List : EInfo_List.Vector) return Boolean;
   --  Return True if List has duplicated entities. Used in assertions.

   Not_Found : exception;

   ---------------------------
   -- Entity_Id subprograms --
   ---------------------------

   function New_Entity
     (Context  : access constant Docgen_Context;
      Language : Language_Access;
      E        : General_Entity;
      Loc      : General_Location) return Entity_Id;
   function New_Internal_Entity
     (Context  : access constant Docgen_Context;
      Language : Language_Access;
      Name     : String) return Entity_Id;
   --  Tree node constructors. New_Internal_Entity is used only to build the
   --  entity associated with the Standard scope, the full-view of private
   --  and incomplete types, and the entity associated with unknown
   --  discriminants of private types.

   procedure Free (E : in out Entity_Id);
   --  Tree node destructor

   procedure Append_Direct_Derivation
     (E : Entity_Id; Value : Entity_Id);
   --  This attribute stores only direct derivations of tagged types (that is,
   --  it stores all the entities for which verify that Parent (Value) = E;
   --  this means that progenitors are NOT stored here). Combined with the
   --  attribute "Parent" this attribute allows to traverse the tree up and
   --  down in the tree of tagged type derivations. If all the derivations of
   --  a type are needed then attribute LL.Get_Child_Types must be used.

   procedure Append_Inherited_Method
     (E : Entity_Id; Value : Entity_Id);
   procedure Append_Method
     (E : Entity_Id; Value : Entity_Id);
   procedure Append_Progenitor
     (E : Entity_Id; Value : Entity_Id);
   procedure Append_To_Scope
     (E : Entity_Id; Value : Entity_Id);
   --  Append Value to the list of entities in the scope of E

   function Get_Alias
     (E : Entity_Id) return Entity_Id;
   function Get_Comment
     (E : Entity_Id) return Structured_Comment;

   function Get_Components
     (E : Entity_Id) return EInfo_List.Vector;
   --  Applicable to record types, concurrent types and concurrent objects

   function Get_Direct_Derivations
     (E : Entity_Id) return access EInfo_List.Vector;

   function Get_Discriminants
     (E : Entity_Id) return EInfo_List.Vector;
   --  Applicable to record types, concurrent types and concurrent objects

   function Get_Doc
     (E : Entity_Id) return Comment_Result;

   function Get_End_Of_Profile_Location
     (E : Entity_Id) return General_Location;
   --  This attribute is set only for subprograms

   function Get_End_Of_Profile_Location_In_Body
     (E : Entity_Id) return General_Location;
   --  This attribute is set only for subprograms

   function Get_End_Of_Syntax_Scope_Loc
     (E : Entity_Id) return General_Location;
   --  At current stage this attribute is set only for E_Package,
   --  E_Generic_Package entities, and concurrent types and objects.

   function Get_Entities
     (E : Entity_Id) return access EInfo_List.Vector;
   function Get_Error_Msg
     (E : Entity_Id) return Unbounded_String;
   function Get_Full_Name
     (E : Entity_Id) return String;
   function Get_Full_View
     (E : Entity_Id) return Entity_Id;
   function Get_Full_View_Comment
     (E : Entity_Id) return Structured_Comment;
   function Get_Full_View_Doc
     (E : Entity_Id) return Comment_Result;
   function Get_Full_View_Src
     (E : Entity_Id) return Unbounded_String;
   function Get_Inherited_Methods
     (E : Entity_Id) return access EInfo_List.Vector;
   function Get_IDepth_Level
     (E : Entity_Id) return Natural;
   function Get_Kind
     (E : Entity_Id) return Entity_Kind;
   function Get_Language
     (E : Entity_Id) return Language_Access;
   function Get_Methods
     (E : Entity_Id) return access EInfo_List.Vector;
   function Get_Parent
     (E : Entity_Id) return Entity_Id;
   function Get_Parent_Package
     (E : Entity_Id) return Entity_Id;
   function Get_Partial_View
     (E : Entity_Id) return Entity_Id;
   function Get_Progenitors
     (E : Entity_Id) return access EInfo_List.Vector;
   function Get_Ref_File
     (E : Entity_Id) return Virtual_File;
   function Get_Scope
     (E : Entity_Id) return Entity_Id;
   function Get_Short_Name
     (E : Entity_Id) return String;

   function Get_Entries
     (E : Entity_Id) return EInfo_List.Vector;
   --  Applicable to concurrent types and concurrent objects
   function Get_Subprograms
     (E : Entity_Id) return EInfo_List.Vector;
   --  Applicable to record types, concurrent types and concurrent objects
   function Get_Subprograms_And_Entries
     (E : Entity_Id) return EInfo_List.Vector;
   --  Applicable to record types, concurrent types and concurrent objects

   function Get_Src
     (E : Entity_Id) return Unbounded_String;
   function Get_Unique_Id
     (E : Entity_Id) return Natural;

   function Has_Private_Parent
     (E : Entity_Id) return Boolean;
   --  True if E has a parent which is visible only in its full view

   function Has_Unknown_Discriminants
     (E : Entity_Id) return Boolean;

   function In_Ada_Language
     (E : Entity_Id) return Boolean;
   function In_C_Or_CPP_Language
     (E : Entity_Id) return Boolean;
   function In_Private_Part
     (E : Entity_Id) return Boolean;

   function Is_Class_Or_Record_Type
     (E : Entity_Id) return Boolean;
   --  Return True for Ada record types (including tagged types and interface
   --  types), C structs and C++ classes
   function Is_Concurrent_Object
     (E : Entity_Id) return Boolean;
   function Is_Concurrent_Type
     (E : Entity_Id) return Boolean;
   function Is_Concurrent_Type_Or_Object
     (E : Entity_Id) return Boolean;
   function Is_Decorated
     (E : Entity_Id) return Boolean;

   function Is_Full_View
     (E : Entity_Id) return Boolean;
   --  Return true if E is the full view of a private or incomplete type

   function Is_Doc_From_Body
     (E : Entity_Id) return Boolean;
   function Is_Generic_Formal
     (E : Entity_Id) return Boolean;
   function Is_Incomplete
     (E : Entity_Id) return Boolean;
   function Is_Package
     (E : Entity_Id) return Boolean;

   function Is_Partial_View
     (E : Entity_Id) return Boolean;
   --  Return true if E is the partial view of a private or incomplete type

   function Is_Private
     (E : Entity_Id) return Boolean;
   function Is_Standard_Entity
     (E : Entity_Id) return Boolean;
   --  Return true if E represents the Standard scope (the outermost entity)
   function Is_Subprogram
     (E : Entity_Id) return Boolean;
   function Is_Subprogram_Or_Entry
     (E : Entity_Id) return Boolean;
   function Is_Subtype
     (E : Entity_Id) return Boolean;
   function Is_Tagged
     (E : Entity_Id) return Boolean;

   function Kind_In
     (K  : Entity_Kind;
      V1 : Entity_Kind;
      V2 : Entity_Kind) return Boolean;
   function Kind_In
     (K  : Entity_Kind;
      V1 : Entity_Kind;
      V2 : Entity_Kind;
      V3 : Entity_Kind) return Boolean;
   function Kind_In
     (K  : Entity_Kind;
      V1 : Entity_Kind;
      V2 : Entity_Kind;
      V3 : Entity_Kind;
      V4 : Entity_Kind) return Boolean;

   procedure Remove_Full_View  (E : Entity_Id);
   procedure Remove_From_Scope (E : Entity_Id);

   procedure Set_Alias
     (E : Entity_Id; Value : Entity_Id);
   procedure Set_Comment
     (E : Entity_Id; Value : Structured_Comment);
   procedure Set_Doc
     (E : Entity_Id; Value : Comment_Result);
   procedure Set_End_Of_Profile_Location
     (E : Entity_Id; Loc : General_Location);
   procedure Set_End_Of_Profile_Location_In_Body
     (E : Entity_Id; Loc : General_Location);
   procedure Set_End_Of_Syntax_Scope_Loc
     (E : Entity_Id; Loc : General_Location);
   --  At current stage this attribute is set only for E_Package,
   --  E_Generic_Package entities, and concurrent types and objects.

   procedure Set_Error_Msg
     (E : Entity_Id; Value : Unbounded_String);
   procedure Set_Full_View
     (E : Entity_Id; Value : Entity_Id);
   procedure Set_Full_View_Comment
     (E : Entity_Id; Value : Structured_Comment);
   procedure Set_Full_View_Doc
     (E : Entity_Id; Value : Comment_Result);
   procedure Set_Full_View_Src
     (E : Entity_Id; Value : Unbounded_String);
   procedure Set_Has_Private_Parent
     (E : Entity_Id; Value : Boolean := True);
   procedure Set_Has_Unknown_Discriminants
     (E : Entity_Id);

   procedure Set_In_Private_Part
     (E : Entity_Id);
   procedure Set_IDepth_Level
     (E : Entity_Id);
   procedure Set_Is_Decorated
     (E : Entity_Id);
   procedure Set_Is_Doc_From_Body
     (E : Entity_Id);
   procedure Set_Is_Generic_Formal
     (E : Entity_Id);
   procedure Set_Is_Incomplete
     (E : Entity_Id; Value : Boolean := True);
   procedure Set_Is_Private
     (E : Entity_Id);
   procedure Set_Is_Subtype
     (E : Entity_Id);
   procedure Set_Is_Tagged
     (E : Entity_Id);
   procedure Set_Kind
     (E : Entity_Id; Value : Entity_Kind);
   procedure Set_Parent
     (E : Entity_Id; Value : Entity_Id);
   procedure Set_Parent_Package
     (E : Entity_Id; Value : Entity_Id);
   procedure Set_Partial_View
     (E : Entity_Id; Value : Entity_Id);
   procedure Set_Ref_File
     (E : Entity_Id; Value : Virtual_File);
   procedure Set_Scope
     (E : Entity_Id; Value : Entity_Id);

   procedure Set_Src
     (E : Entity_Id; Value : Unbounded_String);
   --  Set attribute Src filtering empty lines located at the beginning and
   --  end of Value

   type Traverse_Result is (OK, Skip);

   procedure Traverse_Tree
     (Root    : Entity_Id;
      Process : access function
                         (Entity      : Entity_Id;
                          Scope_Level : Natural) return Traverse_Result);

   --  Given the parent node for a subtree, traverses all nodes of this tree,
   --  calling the given function Process on each one, in pre order (i.e.
   --  top-down). The order of traversing subtrees follows their order in the
   --  attribute Entities. The traversal is controlled as follows by the result
   --  returned by Process:

   --    OK       The traversal continues normally with the children of the
   --             node just processed.

   --    Skip     The children of the node just processed are skipped and
   --             excluded from the traversal, but otherwise processing
   --             continues elsewhere in the tree.

   -----------------------------------
   -- Low-Level abstraction package --
   -----------------------------------

   --  This local package provides the information retrieved directly from the
   --  Xref database when the entity is created. It is named LL (Low Level)
   --  instead of Xref to avoid having a third package in the GPS project
   --  named Xref (the other packages are Xref and GNATCOLL.Xref).

   package LL is
      procedure Append_Child_Type
        (E : Entity_Id; Value : Entity_Id);
      procedure Append_Parent_Type
        (E : Entity_Id; Value : Entity_Id);

      function Get_Alias
        (E : Entity_Id) return General_Entity;
      function Get_Body_Loc
        (E : Entity_Id) return General_Location;
      function Get_Child_Types
        (E : Entity_Id) return access EInfo_List.Vector;
      function Get_End_Of_Scope_Loc
        (E : Entity_Id) return General_Location;
      function Get_Entity
        (E : Entity_Id) return General_Entity;
      function Get_First_Private_Entity_Loc
        (E : Entity_Id) return General_Location;
      function Get_Full_Name
        (E : Entity_Id) return String;
      function Get_Instance_Of
        (E : Entity_Id) return General_Entity;
      function Get_Kind
        (E : Entity_Id) return Entity_Kind;
      function Get_Location
        (E : Entity_Id) return General_Location;
      function Get_Parent_Package
        (E : Entity_Id) return General_Entity;
      function Get_Parent_Types
        (E : Entity_Id) return access EInfo_List.Vector;
      function Get_Pointed_Type
        (E : Entity_Id) return General_Entity;
      function Get_Scope
        (E : Entity_Id) return General_Entity;
      function Get_Scope_Loc
        (E : Entity_Id) return General_Location;
      function Get_Type
        (E : Entity_Id) return General_Entity;

      function Get_Ekind
        (Db          : General_Xref_Database;
         E           : General_Entity;
         In_Ada_Lang : Boolean) return Entity_Kind;
      --  In_Ada_Lang is used to enable an assertion since in Ada we are not
      --  processing bodies yet???

      function Has_Methods
        (E : Entity_Id) return Boolean;
      function Has_Reference
        (E   : Entity_Id;
         Loc : General_Location) return Boolean;
      --  Return True if E is referenced from location Loc

      function Is_Abstract      (E : Entity_Id) return Boolean;
      function Is_Access        (E : Entity_Id) return Boolean;
      function Is_Array         (E : Entity_Id) return Boolean;
      function Is_Container     (E : Entity_Id) return Boolean;
      function Is_Generic       (E : Entity_Id) return Boolean;
      function Is_Global        (E : Entity_Id) return Boolean;
      function Is_Predef        (E : Entity_Id) return Boolean;
      function Is_Primitive     (E : Entity_Id) return Boolean;
      function Is_Type          (E : Entity_Id) return Boolean;

      function Is_Self_Referenced_Type
        (Db   : General_Xref_Database;
         E    : General_Entity;
         Lang : Language_Access) return Boolean;
      --  Return true if Lang is C or C++ and the scope of E is itself. Used to
      --  identify the second second entity generated by the C/C++ compiler for
      --  named typedef structs (the compiler generates two entites in the LI
      --  file with the same name).

      procedure Set_Location
        (E : Entity_Id; Value : General_Location);

   private
      pragma Inline (Append_Child_Type);
      pragma Inline (Append_Parent_Type);

      pragma Inline (Get_Alias);
      pragma Inline (Get_Body_Loc);
      pragma Inline (Get_Child_Types);
      pragma Inline (Get_Entity);
      pragma Inline (Get_First_Private_Entity_Loc);
      pragma Inline (Get_Kind);
      pragma Inline (Get_Location);
      pragma Inline (Get_Parent_Package);
      pragma Inline (Get_Parent_Types);
      pragma Inline (Get_Pointed_Type);
      pragma Inline (Get_Scope);
      pragma Inline (Get_Type);

      pragma Inline (Is_Abstract);
      pragma Inline (Is_Access);
      pragma Inline (Is_Array);
      pragma Inline (Is_Container);
      pragma Inline (Is_Generic);
      pragma Inline (Is_Global);
      pragma Inline (Is_Predef);
      pragma Inline (Is_Primitive);
      pragma Inline (Is_Type);

      pragma Inline (Set_Location);
   end LL;

   ------------------------------------------
   --  Debugging routines (for use in gdb) --
   ------------------------------------------

   procedure Register_Database (Database : General_Xref_Database);
   --  Routine called by gnatdoc.adb to register in this package the database
   --  and thus simplify the use of subprogram "pn" from gdb.

   function name
     (Db : General_Xref_Database;
      E  : General_Entity) return String;
   --  (gdb) Returns the short name of E

   procedure pl (E : Entity_Id);
   --  (gdb) Prints the list of entities defined in the scope of E

   procedure pn (E : Entity_Id);
   --  (gdb) Prints a single tree node (full output), without printing
   --  descendants.

   procedure ploc (E : Entity_Id);
   --  (gdb) Prints the location of E

   procedure pns (E : Entity_Id);
   procedure pns (Db : General_Xref_Database; E : General_Entity);
   --  (gdb) Print a single tree node (short output), without printing
   --  descendants.

   procedure pv (V : EInfo_List.Vector);
   procedure pv (Db : General_Xref_Database; V : Xref.Entity_Array);
   --  (gdb) Using pns print all the elements of V

   function To_String
     (E              : Entity_Id;
      Prefix         : String := "";
      With_Full_Loc  : Boolean := False;
      With_Src       : Boolean := False;
      With_Doc       : Boolean := False;
      With_Errors    : Boolean := False;
      With_Unique_Id : Boolean := False;
      Reliable_Mode  : Boolean := True) return String;
   --  Returns a string containing all the information associated with E.
   --  Prefix is used by routines of package GNATdoc.Treepr to generate the
   --  bar which represents the enclosing scopes. If With_Full_Loc is true then
   --  the full path of the location of the file is added to the output; if
   --  With_Src is true then the source retrieved from the sources is added to
   --  the output; if With_Doc is true then the documentation retrieved from
   --  sources is added to the output; if With_Errors is true then the errors
   --  reported on the node are added to the output; if With_Unique_Id is true
   --  then the unique identifier of E as well as the unique identifier of all
   --  the entities associated with E (ie. Parent, Scope, etc.) is added to
   --  the output. If Reliable_Mode is True then Xref information which is not
   --  fully reliable and can vary between platforms is not added to the output

private
   type Ref_Info is record
      Ref : General_Entity_Reference;
      Loc : General_Location;
   end record;

   package Ref_List is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Ref_Info);

   type Xref_Info is
      record
         Alias            : General_Entity;
         Body_Loc         : General_Location;
         Ekind            : Entity_Kind;
         End_Of_Scope_Loc : General_Location;
         Entity           : General_Entity;
         Etype            : General_Entity;
         Instance_Of      : General_Entity;
         Loc              : General_Location;
         Pointed_Type     : General_Entity;

         Scope_E          : General_Entity;
         Scope_Loc        : General_Location;
         Parent_Package   : General_Entity;
         --  Present in packages

         First_Private_Entity_Loc : General_Location;

         Parent_Types  : aliased EInfo_List.Vector;
         --  Parent types of tagged types (or base classes of C++ classes)

         Child_Types   : aliased EInfo_List.Vector;
         --  Derivations of tagged types (or C++ classes)

         References    : aliased Ref_List.Vector;

         Has_Methods   : Boolean;

         Is_Abstract   : Boolean;
         Is_Access     : Boolean;
         Is_Array      : Boolean;
         Is_Container  : Boolean;
         Is_Global     : Boolean;
         Is_Predef     : Boolean;
         Is_Type       : Boolean;
         Is_Subprogram : Boolean;
         Is_Primitive  : Boolean;
         Is_Generic    : Boolean;
      end record;

   type Entity_Info_Record is
      record
         Id : Natural;
         --  Internal unique identifier associated with each entity. Given
         --  that GNATdoc routines are executed by a single thread, and given
         --  that their behavior is deterministic, this unique identifier
         --  facilitates setting breakpoints in the debugger using this Id.
         --
         --  This unique identifier may be also used by the backend to
         --  generate unique labels in the ReST output (to avoid problems
         --  with overloaded entities). For examples see Backend.Simple.

         Language : Language_Access;
         --  Language associated with the entity. It can be used by the backend
         --  to generate full or short names depending on the language. For
         --  examples see Backend.Simple.

         Ref_File : Virtual_File;
         --  File associated with this entity for backend references.
         --  * For Ada entities this value is the same of Loc.File.
         --  * For C/C++ entities defined in header files, the value of
         --    Loc.File references the .h file, which is a file for which the
         --    compiler does not generate LI files). Hence the frontend stores
         --    in this field the file which must be referenced by the backend.
         --    (that is, the corresponding .c or .cpp file). For entities
         --    defined in the .c (or .cpp) files the values of Loc.File and
         --    File are identical.

         --       Warning: The values of Id and Ref_File are used by the
         --       backend to generate valid and unique cross references
         --       between generated reST files.

         Kind            : Entity_Kind;
         --  When the entity is created the fields Kind and Xref.Ekind are
         --  initialized with the same values. However, Kind may be decorated
         --  with other values by the frontend at later stages based on the
         --  context (for example, an E_Variable entity may be redecorated
         --  as E_Formal (see gnatdoc-frontend.adb)

         Alias           : Entity_Id;
         Scope           : Entity_Id;
         Parent_Package  : Entity_Id;
         --  Present in packages

         End_Of_Syntax_Scope_Loc         : General_Location;
         End_Of_Profile_Location         : General_Location;
         End_Of_Profile_Location_In_Body : General_Location;

         Full_Name       : GNATCOLL.Symbols.Symbol;
         Short_Name      : GNATCOLL.Symbols.Symbol;

         Has_Private_Parent : Boolean;
         --  True if the parent type is only visible in the full view

         Has_Unknown_Discriminants : Boolean;

         In_Private_Part   : Boolean;
         --  True if the entity is defined in the private part of a package

         Is_Decorated      : Boolean;
         Is_Generic_Formal : Boolean;
         Is_Internal       : Boolean;
         Is_Incomplete     : Boolean;
         Is_Private        : Boolean;

         Is_Subtype        : Boolean;
         Is_Tagged_Type    : Boolean;
         Idepth_Level      : Natural;
         --  Inheritance depth level of a tagged type

         Doc               : Comment_Result;
         Is_Doc_From_Body  : Boolean;
         Comment           : aliased Structured_Comment;
         --  Doc is a temporary buffer used to store the block of comments
         --  retrieved from the source file. After processed, it is cleaned and
         --  its contents is stored in the structured comment, which identifies
         --  tags and attributes.

         Full_View         : Entity_Id;
         Partial_View      : Entity_Id;

         Full_View_Doc     : Comment_Result;
         Full_View_Comment : aliased Structured_Comment;
         --  Same as before but applicable to the documentation and structured
         --  comment associated with the full-view.

         Src             : Unbounded_String;
         Full_View_Src   : Unbounded_String;
         --  Source code associated with this entity (and its full-view)

         Entities        : aliased EInfo_List.Vector;
         --  Entities defined in the scope of this entity. For example, all
         --  the entities defined in the scope of a package, all the components
         --  of a record, etc.

         Methods           : aliased EInfo_List.Vector;
         Inherited_Methods : aliased EInfo_List.Vector;
         --  Primitives of tagged types (or methods of C++ classes)

         Parent             : Entity_Id;
         Progenitors        : aliased EInfo_List.Vector;
         Direct_Derivations : aliased EInfo_List.Vector;

         Error_Msg       : Unbounded_String;
         --  Errors reported on this entity

         Xref            : Xref_Info;
         --  Information retrieved directly from the Xref database.

      end record;

   pragma Inline (Append_Direct_Derivation);
   pragma Inline (Append_Inherited_Method);
   pragma Inline (Append_Method);
   pragma Inline (Append_Progenitor);
   pragma Inline (Append_To_Scope);

   pragma Inline (Get_Alias);
   pragma Inline (Get_Comment);
   pragma Inline (Get_Direct_Derivations);
   pragma Inline (Get_Doc);
   pragma Inline (Get_End_Of_Profile_Location);
   pragma Inline (Get_End_Of_Profile_Location_In_Body);
   pragma Inline (Get_End_Of_Syntax_Scope_Loc);
   pragma Inline (Get_Entities);
   pragma Inline (Get_Error_Msg);
   pragma Inline (Get_Full_Name);
   pragma Inline (Get_Full_View);
   pragma Inline (Get_Full_View_Comment);
   pragma Inline (Get_Full_View_Doc);
   pragma Inline (Get_Full_View_Src);
   pragma Inline (Get_Inherited_Methods);
   pragma Inline (Get_IDepth_Level);
   pragma Inline (Get_Kind);
   pragma Inline (Get_Language);
   pragma Inline (Get_Methods);
   pragma Inline (Get_Parent);
   pragma Inline (Get_Parent_Package);
   pragma Inline (Get_Partial_View);
   pragma Inline (Get_Progenitors);
   pragma Inline (Get_Ref_File);
   pragma Inline (Get_Scope);
   pragma Inline (Get_Short_Name);
   pragma Inline (Get_Src);
   pragma Inline (Get_Unique_Id);
   pragma Inline (Has_Private_Parent);
   pragma Inline (Has_Unknown_Discriminants);
   pragma Inline (In_Ada_Language);
   pragma Inline (In_C_Or_CPP_Language);
   pragma Inline (In_Private_Part);
   pragma Inline (Is_Class_Or_Record_Type);
   pragma Inline (Is_Concurrent_Object);
   pragma Inline (Is_Concurrent_Type);
   pragma Inline (Is_Concurrent_Type_Or_Object);
   pragma Inline (Is_Decorated);
   pragma Inline (Is_Doc_From_Body);
   pragma Inline (Is_Full_View);
   pragma Inline (Is_Generic_Formal);
   pragma Inline (Is_Incomplete);
   pragma Inline (Is_Package);
   pragma Inline (Is_Partial_View);
   pragma Inline (Is_Private);
   pragma Inline (Is_Subprogram);
   pragma Inline (Is_Subtype);
   pragma Inline (Is_Tagged);
   pragma Inline (Kind_In);
   pragma Inline (No);
   pragma Inline (Present);
   pragma Inline (Set_Alias);
   pragma Inline (Set_Comment);
   pragma Inline (Set_In_Private_Part);
   pragma Inline (Set_IDepth_Level);
   pragma Inline (Set_Doc);
   pragma Inline (Set_End_Of_Profile_Location);
   pragma Inline (Set_End_Of_Profile_Location_In_Body);
   pragma Inline (Set_End_Of_Syntax_Scope_Loc);
   pragma Inline (Set_Error_Msg);
   pragma Inline (Set_Full_View);
   pragma Inline (Set_Full_View_Comment);
   pragma Inline (Set_Full_View_Doc);
   pragma Inline (Set_Full_View_Src);
   pragma Inline (Set_Has_Private_Parent);
   pragma Inline (Set_Has_Unknown_Discriminants);
   pragma Inline (Set_Is_Decorated);
   pragma Inline (Set_Is_Doc_From_Body);
   pragma Inline (Set_Is_Generic_Formal);
   pragma Inline (Set_Is_Incomplete);
   pragma Inline (Set_Is_Private);
   pragma Inline (Set_Is_Subtype);
   pragma Inline (Set_Is_Tagged);
   pragma Inline (Set_Kind);
   pragma Inline (Set_Parent);
   pragma Inline (Set_Parent_Package);
   pragma Inline (Set_Partial_View);
   pragma Inline (Set_Ref_File);
   pragma Inline (Set_Scope);
   pragma Inline (Set_Src);
end GNATdoc.Atree;
