﻿note
	description: "[
		Implementation of multiple inheritance by using multiple inheritance
		of interfaces. No simple inheritance of implementation is performed
	]"
	legal: "See notice at end of class."
	status: "See notice at end of class."
	date: "$Date$"
	revision: "$Revision$"

class
	INTERFACE_IL_CODE_GENERATOR

inherit
	CIL_CODE_GENERATOR
		redefine
			make
		end

create
	make

feature {NONE} -- Initialization

	make
			-- Initialize generator.
		do
			Precursor {CIL_CODE_GENERATOR}
			create processed_tbl.make (20)
			create rout_ids_tbl.make (50)
		end

feature {NONE} -- Access

	is_single_inheritance_implementation: BOOLEAN = False
			-- Multiple interface code generation.

	rout_ids_tbl: HASH_TABLE [FEATURE_I, INTEGER]
			-- Table of FEATURE_I indexed by routine IDs, to quickly find out
			-- if a FEATURE_I with a given routine ID has already been generated
			-- in `currrent_class_type'. If so, a MethodImpl is defined on
			-- generated routine. Otherwise, we have to traverse `current_select_tbl'
			-- to find associated FEATURE_I and generate a new feature.

	processed_tbl: SEARCH_TABLE [INTEGER]
			-- Record CLASS_TYPEs that have been processed regarding inherited
			-- routines. Indexed by `CLASS_TYPE.static_type_id'.

	current_select_tbl: SELECT_TABLE
			-- Current feature table associated with `current_class_type'.

feature -- IL Generation

	generate_il_features (class_c: CLASS_C; class_type: CLASS_TYPE;
			implemented_feature_processor: PROCEDURE [FEATURE_I, CLASS_TYPE, FEATURE_I];
			local_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE, BOOLEAN];
			inherited_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE];
			type_feature_processor: PROCEDURE [TYPE_FEATURE_I];
			inline_agent_processor: PROCEDURE [FEATURE_I])

			-- Generate IL code for feature in `class_c'.
		local
			class_interface: CLASS_INTERFACE
			f: FEATURE_I
			gt: INTEGER
			st: INTEGER
			pt: INTEGER
			tid: INTEGER
			fid: INTEGER
			p: PAIR [INTEGER, INTEGER]
			ct: INTEGER
			t: TYPE_A
		do
				-- Reset data
			rout_ids_tbl.wipe_out
			processed_tbl.wipe_out

				-- Initialize implementation.
			set_current_type_id (class_type.implementation_id)
			current_class_token := actual_class_type_token (current_type_id)
			current_select_tbl := class_c.feature_table.select_table

				-- First generate anchored features as they might be needed by current class
				-- features for code generation when current class is frozen.
			generate_il_type_features (class_c, class_type, class_c.generic_features, type_feature_processor)
			generate_il_type_features (class_c, class_type, class_c.anchored_features, type_feature_processor)

				-- Generate features for inline agents.
			if class_c.is_eiffel_class_c then
				generate_il_inline_agents (class_c.eiffel_class_c, inline_agent_processor)
			end

				-- Generate current features implement locally in `current_class_type'
				-- and traverse parents to define inherited features.
			class_interface := class_type.class_interface
			generate_il_implementation_local (class_interface, class_c, class_type,
				local_feature_processor, inherited_feature_processor)
			generate_il_implementation_parents (class_interface, implemented_feature_processor,
				local_feature_processor, inherited_feature_processor)

			across
				postponed_property_setters as s
			loop
				p := s.item
				fid := p.first
				tid := p.second
				current_module.insert_property_setter
					(feature_token (tid, current_class.feature_of_feature_id
						(fid).property_setter_in (current_class_type).feature_id), tid, fid)
			end
			postponed_property_setters.wipe_out

			tid := class_type.static_type_id
			ct := actual_class_type_token (tid)
			across
				properties as property
			loop
				fid := property.item
				f := current_class.feature_of_feature_id (fid)
				uni_string.set_string (f.property_name)
				property_sig.reset
				property_sig.set_property_type ({MD_SIGNATURE_CONSTANTS}.property_sig | {MD_SIGNATURE_CONSTANTS}.has_current)
				property_sig.set_parameter_count (0)
				t := result_type_in (f, class_type)
				if t.is_void then
					t := argument_actual_type_in (f.arguments.first, class_type)
				end
				set_signature_type (property_sig, t, class_type)
				st := current_module.defined_property_setter_token (tid, fid)
				if st & {MD_TOKEN_TYPES}.md_method_def = 0 then
					st := {MD_TOKEN_TYPES}.md_method_def
				end
				gt := current_module.defined_property_getter_token (tid, fid)
				if gt & {MD_TOKEN_TYPES}.md_method_def = 0 then
					gt := {MD_TOKEN_TYPES}.md_method_def
				end
				pt := md_emit.define_property (ct, uni_string, 0, property_sig, st, gt)
				if attached f.property_custom_attributes as ca then
					{CUSTOM_ATTRIBUTE_FACTORY}.generate_custom_attributes (pt, ca)
				end
			end
			properties.wipe_out

				-- Reset global variable for collection.
			current_select_tbl := Void
			rout_ids_tbl.wipe_out
			processed_tbl.wipe_out
		end

	generate_il_implementation (class_c: CLASS_C; class_type: CLASS_TYPE)
			-- Generate IL code for feature in `class_c'.
		do
				-- Initialize context.
			set_current_class_type (class_type)
			inst_context.set_group (class_c.group)
			is_single_class := class_type.is_generated_as_single_type

				-- Generate features.
			generate_il_features (class_c, class_type,
				agent generate_method_impl,
				agent generate_local_feature,
				agent generate_inherited_feature,
				agent generate_type_feature,
				agent generate_feature_code (?, True))
				-- Generate class invariant and internal run-time features.
			generate_class_features (class_c, class_type)

				-- Generates class constructor(s)
			define_constructors (class_type, False)

				-- Reset global variable for collection.
			current_class_type := Void
		end

	generate_il_type_features (class_c: CLASS_C; class_type: CLASS_TYPE;
			type_features: HASH_TABLE [TYPE_FEATURE_I, INTEGER]; type_feature_processor: PROCEDURE [TYPE_FEATURE_I])
			-- Generate IL code for feature that represents type information of `class_c'.
		require
			class_c_not_void: class_c /= Void
			class_type_not_void: class_type /= Void
		do
			if attached type_features and then attached type_feature_processor then
				⟳ f: type_features ¦ type_feature_processor (f) ⟲
			end
		end

	generate_il_implementation_parents (class_interface: CLASS_INTERFACE;
			implemented_feature_processor: PROCEDURE [FEATURE_I, CLASS_TYPE, FEATURE_I];
			local_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE, BOOLEAN];
			inherited_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE])

			-- Generate IL code for feature in `class_c'.
		require
			class_interface_not_void: class_interface /= Void
			local_feature_processor_not_void: local_feature_processor /= Void
			inherited_feature_processor_not_void: inherited_feature_processor /= Void
		local
			l_interface: CLASS_INTERFACE
			l_cl_type: CLASS_TYPE
		do
			across
				class_interface.parents as p
			loop
				l_interface := p.item
				l_cl_type := l_interface.class_type
				if not processed_tbl.has (l_cl_type.static_type_id) then
					processed_tbl.put (l_cl_type.static_type_id)
					generate_il_implementation_inherited (l_interface, l_interface.associated_class, l_cl_type,
						implemented_feature_processor, local_feature_processor, inherited_feature_processor)
					generate_il_implementation_parents (l_interface,
						implemented_feature_processor, local_feature_processor, inherited_feature_processor)
				end
			end
		end

	generate_il_implementation_local
			(class_interface: CLASS_INTERFACE; class_c: CLASS_C;
			class_type: CLASS_TYPE;
			local_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE, BOOLEAN];
			inherited_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE])

			-- Generate IL code for inherited features of `current_class_type'.
		require
			class_c_not_void: class_c /= Void
			class_type_not_void: class_type /= Void
			not_external_class_type: not class_type.is_external
		local
			select_tbl: SELECT_TABLE
			feat: FEATURE_I
			l_class_id: INTEGER
		do
				-- Generate code
			select_tbl := class_c.feature_table.select_table
			l_class_id := current_class_type.type.class_id
			across
				class_interface.features as f
			loop
				feat := select_tbl.item (f.item)
					-- Generate code for current class only.
				if not feat.is_deferred then
					if feat.written_in = l_class_id or feat.is_attribute or feat.is_object_relative_once then
						local_feature_processor.call ([feat, Void, class_type, False])
					elseif feat.is_replicated and feat.is_unselected then
						local_feature_processor.call ([feat, Void, class_type, True])
					elseif feat.is_replicated_directly then
						local_feature_processor.call ([feat, Void, class_type, True])
					else
							-- Case of local renaming or implicit covariant redefinition.
						inherited_feature_processor.call ([feat, Void, class_type])
					end
					mark_as_treated (feat)
				else
						-- Nothing to be done here. Parent was deferred and we
						-- are still deferred. It should only happen when
						-- generating a deferred class.
					check
						deferred_class:
							current_class_type.associated_class.is_deferred
					end
				end
			end
		end

	generate_il_implementation_inherited
			(class_interface: CLASS_INTERFACE; class_c: CLASS_C; class_type: CLASS_TYPE;
			implemented_feature_processor: PROCEDURE [FEATURE_I, CLASS_TYPE, FEATURE_I];
			local_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE, BOOLEAN];
			inherited_feature_processor: PROCEDURE [FEATURE_I, FEATURE_I, CLASS_TYPE])

			-- Generate IL code for inherited features of `current_class_type'.
		require
			class_c_not_void: class_c /= Void
			class_type_not_void: class_type /= Void
			local_feature_processor_not_void: local_feature_processor /= Void
			inherited_feature_processor_not_void: inherited_feature_processor /= Void
		local
			select_tbl: SELECT_TABLE
			inh_feat, feat: FEATURE_I
			rout_id, l_class_id: INTEGER
		do
				-- Generate code
			select_tbl := class_c.feature_table.select_table
			l_class_id := current_class_type.type.class_id
			across
				class_interface.features as f
			loop
				inh_feat := select_tbl.item (f.item)
					-- Generate local definition of `inh_feat' which
					-- calls static definition.
				rout_id := inh_feat.rout_id_set.first
				if rout_ids_tbl.has_key (rout_id) then
					if implemented_feature_processor /= Void then
						feat := rout_ids_tbl.found_item
						implemented_feature_processor.call ([feat, class_type, inh_feat])
					end
				else
					feat := current_select_tbl.item (rout_id)
						-- Generate code for current class only.
					if feat /= Void and then feat.is_il_external then
						if
							inherited_feature_processor /= Void and then
							inh_feat.is_deferred and then
							not feat.written_class.conform_to (inh_feat.written_class)
						then
								-- Implementation of the feature has to be generated.
							inherited_feature_processor.call ([feat, inh_feat, class_type])
						end
					elseif feat /= Void and then not feat.is_deferred then
						if feat.written_in = l_class_id or else feat.is_attribute then
							local_feature_processor.call ([feat, inh_feat, class_type, False])
							mark_as_treated (feat)
						else
								-- Case of local renaming or implicit covariant redefinition.
								-- Except that we do not generate redefinition of `finalize'
								-- from SYSTEM_OBJECT in ANY if `current_class' does not
								-- conform to DISPOSABLE. This enables a speed up by about
								-- 30/40% at execution time because .NET GC really slows down
								-- when you define `Finalize' in a descendant of SYSTEM_OBJECT.
							if
								not feat.rout_id_set.has (System.object_finalize_id)
								or else System.disposable_descendants.has (current_class)
							then
								inherited_feature_processor.call ([feat, inh_feat, class_type])
								mark_as_treated (feat)
							end
						end
					else
							-- Nothing to be done here. Parent was deferred and we
							-- are still deferred. It should only happen when
							-- generating a deferred class.
						check
							deferred_class:
								current_class_type.associated_class.is_deferred or else
									inh_feat.is_il_external or else
									(feat = Void or else feat.is_il_external)
						end
					end
				end
			end
		end

	generate_local_feature (feat, inh_feat: FEATURE_I; class_type: CLASS_TYPE; is_replicated: BOOLEAN)
			-- Generate a feature `feat' implemented in `current_class_type', ie
			-- generate encapsulation that calls its static implementation.
		require
			feat_not_void: feat /= Void
			class_type_not_void: class_type /= Void
			parent_class_not_expanded: inh_feat /= Void implies not class_type.is_expanded
		local
			l_is_method_impl_generated: BOOLEAN
			is_expanded: BOOLEAN
			impl_feat: FEATURE_I
			impl_type: CL_TYPE_A
			impl_class_type: CLASS_TYPE
			written_class_type: CLASS_TYPE
		do
			is_expanded := current_class_type.is_expanded
			if feat.body_index = standard_twin_body_index then
				generate_feature_standard_twin (feat)
			else
				impl_feat := inh_feat
				impl_class_type := class_type
				if is_replicated then
						-- Calculate class type where the feature is written.
					written_class_type := current_class_type.type.implemented_type
						(feat.written_in).associated_class_type (Void)
				end
				if not is_single_class then
						-- Generate static definition of a routine `feat' if the class type is not expanded.
					if
						(not is_replicated or else feat.is_once or else feat.is_replicated_directly) and then
						(not is_expanded or else feat.is_attribute or else feat.is_external)
					then
						generate_feature (feat, False, True, False)
						if is_replicated then
							byte_context.change_class_type_context (current_class_type, current_class_type.type,
								written_class_type, written_class_type.type)
						end
						generate_feature_code (feat, True)
						if is_replicated then
							byte_context.restore_class_type_context
						end
					end

						-- Generate local definition of `feat' which
						-- calls static definition.
					if inh_feat /= Void then
						l_is_method_impl_generated := is_method_impl_needed (feat, inh_feat, class_type)
							or else is_local_signature_changed (inh_feat, feat)
					end

					if is_expanded and then not feat.is_attribute and then not feat.is_external then
						if is_replicated and then not feat.is_replicated_directly then
							byte_context.change_class_type_context (current_class_type,
								current_class_type.type,
								written_class_type, written_class_type.type)
						end
						generate_feature_code (feat, False)
						if is_replicated and then not feat.is_replicated_directly then
							byte_context.restore_class_type_context
						end
					elseif not is_replicated or else feat.is_once or else feat.is_replicated_directly then
							-- We call locally above generated static feature
						generate_feature_il (feat,
							current_class_type.implementation_id,
							feat.feature_id)
					else
							-- We call static feature corresponding to current replicated feature.
							-- This static feature is defined in parent which explains the search
							-- made below to find in which parent's type.
						generate_feature_il (feat,
							written_class_type.implementation_id,
							feat.written_feature_id)
					end
				else
					if is_expanded then
						if inh_feat = Void then
								-- Generate implementation for reference counterpart of this class.
							impl_type := current_class_type.type.reference_type
							impl_class_type := impl_type.associated_class_type (Void)
								-- Update `feat' in the context of the reference type and use it as `impl_feat'.
							impl_feat := feat.instantiation_in (impl_type)
						else
								-- Generate implementation for parent class type.
							impl_feat := inh_feat
							impl_class_type := class_type
						end
						check
							impl_class_type_is_reference: not impl_class_type.is_expanded
						end
 					end
					if impl_feat /= Void then
						l_is_method_impl_generated := is_method_impl_needed (feat, impl_feat, impl_class_type)
							or is_local_signature_changed (impl_feat, feat)
					end
					if feat.is_c_external then
						if is_replicated then
							generate_feature_il (feat,
								written_class_type.implementation_id,
								feat.written_feature_id)
						else
							generate_feature (feat, False, True, True)
							generate_external_il (feat)
						end
					elseif is_expanded and then feat.is_attribute then
						generate_feature_il (feat,
							current_class_type.implementation_id,
							feat.feature_id)
					else
						if is_replicated then
							byte_context.change_class_type_context (current_class_type, current_class_type.type,
								written_class_type, written_class_type.type)
						end
						generate_feature_code (feat, True)
						if is_replicated then
							byte_context.restore_class_type_context
						end
					end
				end
				if l_is_method_impl_generated then
						-- We need a MethodImpl here for mapping
						-- inherited method to current defined one.
					generate_method_impl (feat, impl_class_type, impl_feat)
				end
				generate_property (feat, inh_feat, class_type, not l_is_method_impl_generated)
			end
		end

	generate_inherited_feature (feat, inh_feat: FEATURE_I; class_type: CLASS_TYPE)
			-- Generate a feature `feat' implemented in `class_type', ie generate
			-- encapsulation that calls its static implementation,
			-- otherwise parent implementation.
		require
			feat_not_void: feat /= Void
			class_type_not_void: class_type /= Void
		local
			l_is_method_impl_generated: BOOLEAN
			implementation_class_id: INTEGER
			implementation_feature_id: INTEGER
			old_class_type: CLASS_TYPE
		do
			if not is_single_class or inh_feat /= Void then
				if inh_feat /= Void then
					l_is_method_impl_generated := is_method_impl_needed (feat, inh_feat, class_type) or else
						is_local_signature_changed (inh_feat, feat)
				end
				if feat.body_index = standard_twin_body_index then
					generate_feature_standard_twin (feat)
				elseif current_class_type.is_expanded and then not feat.is_c_external then
					if feat.written_in /= byte_context.current_type.class_id then
						old_class_type := byte_context.class_type
						byte_context.set_class_type (
							system.class_of_id (feat.written_in).meta_type (current_class_type))
					end
					generate_feature_code (feat, False)
				else
					if feat.is_once or else feat.is_replicated_directly then
						implementation_class_id := feat.access_in
						implementation_feature_id := system.class_of_id (
							implementation_class_id).feature_table.feature_of_rout_id_set (feat.rout_id_set).feature_id
					elseif feat.has_replicated_ast then
							-- We need to retrieve class where replicated AST is initially generated.
						implementation_class_id := feat.access_in
						implementation_feature_id := system.class_of_id (
							implementation_class_id).feature_table.feature_of_rout_id_set (feat.rout_id_set).feature_id
					else
						implementation_class_id := feat.written_in
						implementation_feature_id := feat.written_feature_id
					end
					generate_feature_il (feat,
						current_class_type.type.implemented_type
							(implementation_class_id).implementation_id (Void),
						implementation_feature_id)
				end
				if old_class_type /= Void then
					byte_context.set_class_type (old_class_type)
				end

					-- We need a MethodImpl here for mapping
					-- inherited method to current defined one.
				if l_is_method_impl_generated then
					generate_method_impl (feat, class_type, inh_feat)
				end
			else
				check
					valid: is_single_class and then inh_feat = Void
				end
				if current_class_type.is_expanded then
					if feat.written_in /= byte_context.current_type.class_id then
						old_class_type := byte_context.class_type
						byte_context.set_class_type (
							system.class_of_id (feat.written_in).meta_type (current_class_type))
					end
					generate_feature_code (feat, False)
				else
					generate_feature_il (feat,
						current_class_type.type.implemented_type
							(feat.written_in).associated_class_type (Void).implementation_id,
							feat.written_feature_id)
				end
				if old_class_type /= Void then
					byte_context.set_class_type (old_class_type)
				end
			end
			generate_property (feat, inh_feat, class_type, not l_is_method_impl_generated)
		end

	mark_as_treated (feat: FEATURE_I)
			-- Add `feat' to `rout_ids_tbl' for each routine ID in `rout_id_set' of `feat'.
		local
			rout_id_set: ROUT_ID_SET
			i, nb: INTEGER
		do
			from
				rout_id_set := feat.rout_id_set
				i := 1
				nb := rout_id_set.count
			until
				i > nb
			loop
				check
					not rout_ids_tbl.has (rout_id_set.item (i))
				end
				rout_ids_tbl.put (feat, rout_id_set.item (i))
				i := i + 1
			end
		end

note
	ca_ignore: "CA011", "CA011: too many arguments"
	copyright:	"Copyright (c) 1984-2021, Eiffel Software"
	license:	"GPL version 2 (see http://www.eiffel.com/licensing/gpl.txt)"
	licensing_options:	"http://www.eiffel.com/licensing"
	copying: "[
			This file is part of Eiffel Software's Eiffel Development Environment.
			
			Eiffel Software's Eiffel Development Environment is free
			software; you can redistribute it and/or modify it under
			the terms of the GNU General Public License as published
			by the Free Software Foundation, version 2 of the License
			(available at the URL listed under "license" above).
			
			Eiffel Software's Eiffel Development Environment is
			distributed in the hope that it will be useful, but
			WITHOUT ANY WARRANTY; without even the implied warranty
			of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
			See the GNU General Public License for more details.
			
			You should have received a copy of the GNU General Public
			License along with Eiffel Software's Eiffel Development
			Environment; if not, write to the Free Software Foundation,
			Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
		]"
	source: "[
			Eiffel Software
			5949 Hollister Ave., Goleta, CA 93117 USA
			Telephone 805-685-1006, Fax 805-685-6869
			Website http://www.eiffel.com
			Customer support http://support.eiffel.com
		]"

end
