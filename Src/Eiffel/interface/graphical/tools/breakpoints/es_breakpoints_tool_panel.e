﻿note
	description: "Tool that displays breakpoints"
	legal: "See notice at end of class."
	status: "See notice at end of class."
	author: "$Author$"
	date: "$Date$"
	revision: "$Revision$"

class
	ES_BREAKPOINTS_TOOL_PANEL

inherit
	ES_DOCKABLE_TOOL_PANEL [EV_VERTICAL_BOX]
		redefine
			create_mini_tool_bar_items,
			on_after_initialized,
			internal_recycle,
			on_show
		end

	ES_HELP_CONTEXT
		export
			{NONE} all
		end

	EB_VETO_FACTORY

	EB_SHARED_DEBUGGER_MANAGER
		export
			{NONE} all
		end

	SHARED_EIFFEL_PROJECT
		export
			{NONE} all
		end

	SHARED_WORKBENCH
		export
			{NONE} all
		end

create
	make

feature {NONE} -- Initialization

	build_tool_interface (a_widget: EV_VERTICAL_BOX)
			-- Builds the tools user interface elements.
			-- Note: This function is called prior to showing the tool for the first time.
			--
			-- `a_widget': A widget to build the tool interface using.
		local
			box: EV_VERTICAL_BOX
			g: like grid
		do
			row_highlight_bg_color := Preferences.debug_tool_data.row_highlight_background_color
			set_row_highlight_bg_color_agent := agent set_row_highlight_bg_color
			Preferences.debug_tool_data.row_highlight_background_color_preference.change_actions.extend (set_row_highlight_bg_color_agent)

			create box
			box.set_padding (3)

			create g
			grid := g
			box.extend (g)
			create_filter_bar (a_widget)
			a_widget.extend (box)


				--| Grid building
			g.enable_tree
			g.enable_multiple_row_selection
			g.enable_border
			g.enable_partial_dynamic_content
			g.set_dynamic_content_function (agent computed_grid_item)
			g.enable_default_tree_navigation_behavior (True, True, True, True)
			g.key_press_actions.extend (agent key_pressed_on_grid)

			g.set_column_count_to (4)
			g.column (Data_column_index).set_title (interface_names.l_data)
			g.column (Status_column_index).set_title (interface_names.l_status)
			g.column (Details_column_index).set_title (interface_names.l_details)
			g.column (Tags_column_index).set_title (interface_names.l_tags)

			g.set_auto_resizing_column (Data_column_index, True)
			g.set_auto_resizing_column (Status_column_index, True)
			g.set_auto_resizing_column (Details_column_index, True)
			g.set_auto_resizing_column (Tags_column_index, True)

			register_action (g.row_expand_actions, agent (a_row: EV_GRID_ROW) do grid.request_columns_auto_resizing end)
			register_action (g.row_collapse_actions, agent (a_row: EV_GRID_ROW) do grid.request_columns_auto_resizing end)

			g.set_item_pebble_function (agent on_item_pebble_function)
			g.set_item_accept_cursor_function (agent on_item_pebble_accept_cursor)
			g.set_item_deny_cursor_function (agent on_item_pebble_deny_cursor)

			register_action (g.drop_actions, agent on_stone_dropped)
			g.drop_actions.set_veto_pebble_function (agent can_drop_debuggable_feature_or_class)

			g.build_delayed_cleaning
			g.set_delayed_cleaning_action (agent clean_breakpoints_info)

			g.set_configurable_target_menu_mode
			g.set_configurable_target_menu_handler (agent (develop_window.menus.context_menu_factory).standard_compiler_item_menu)

		end

	create_filter_bar (a_widget: EV_BOX)
			-- Create filter bar
		local
			tags_tf: EVS_TAGS_FIELD
		do
			create tags_tf
			tags_tf.set_provider (debugger_manager.breakpoints_manager.tags_provider)
			tags_tf.set_pixmap (pixmaps.mini_pixmaps.general_edit_icon)

			create filter_bar
			filter_bar.set_border_width (layout_constants.small_border_size)
			filter_bar.set_padding_width (layout_constants.small_padding_size)

			filter_bar.extend (create {EV_LABEL}.make_with_text (interface_names.l_filter))
			filter_bar.disable_item_expand (filter_bar.last)
			filter_bar.extend (tags_tf)

			tags_tf.change_actions.extend (agent (tf: EVS_TAGS_FIELD)
					do
						if tf.is_modified then
							tf.validate_changes
							filter := tf.used_tags
							refresh_breakpoints_info
						end
					end(tags_tf))

			a_widget.extend (filter_bar)
			a_widget.disable_item_expand (filter_bar)
			filter_bar.hide
		end

    create_mini_tool_bar_items: ARRAYED_LIST [SD_TOOL_BAR_ITEM]
            -- Retrieves a list of tool bar items to display on the window title
		local
			dbgm: EB_DEBUGGER_MANAGER
			scmd: EB_STANDARD_CMD
        do
			create Result.make (4)

			dbgm := Eb_debugger_manager

			create scmd.make
			scmd.set_pixel_buffer (pixmaps.mini_pixmaps.completion_filter_icon_buffer)
			scmd.set_mini_pixel_buffer (pixmaps.mini_pixmaps.completion_filter_icon_buffer)
			scmd.set_mini_pixmap (pixmaps.mini_pixmaps.completion_filter_icon)
			scmd.set_tooltip ("filtering breakpoints")
			scmd.add_agent (agent on_filter_clicked)
			scmd.enable_sensitive
			filter_command := scmd

			Result.extend (scmd.new_mini_sd_toolbar_item)

			if dbgm.enable_bkpt /= Void then
				enable_bkpt_button := dbgm.enable_bkpt.new_mini_sd_toolbar_item
				Result.extend (enable_bkpt_button)
			end
			if dbgm.disable_bkpt /= Void then
				disable_bkpt_button := dbgm.disable_bkpt.new_mini_sd_toolbar_item
				Result.extend (disable_bkpt_button)
			end
			if dbgm.clear_bkpt /= Void then
				clear_bkpt_button := dbgm.clear_bkpt.new_mini_sd_toolbar_item
				Result.extend (clear_bkpt_button)
			end
        end

	on_after_initialized
			-- Use to perform additional creation initializations, after the UI has been created.
		do
			Precursor {ES_DOCKABLE_TOOL_PANEL}

				-- FIXME: Tool should be refactored to implement {ES_DOCKABLE_STONEABLE_TOOL_PANEL}
			register_action (content.drop_actions, agent on_stone_dropped)
			content.drop_actions.set_veto_pebble_function (agent can_drop_debuggable_feature_or_class)

			enable_sorting

				-- Set button states based on session data
			if
				attached develop_window_session_data as w_session_data and then
				attached {STRING} w_session_data.value (columns_sorting_data_session_id) as s
			then
				grid_wrapper.set_sorting_status (grid_wrapper.sorted_columns_from_string (s))
			end

			update
		end

feature -- Access: Help

	help_context_id: STRING_32
			-- <Precursor>
		once
			Result := {STRING_32} "9FA30DD2-231F-C1F2-4139-F8E90DF0E77F"
		end

feature {NONE} -- Factory

    create_widget: EV_VERTICAL_BOX
            -- Create a new container widget upon request.
            -- Note: You may build the tool elements here or in `build_tool_interface'
        do
        	Create Result
        end

	create_tool_bar_items: ARRAYED_LIST [SD_TOOL_BAR_ITEM]
			-- Retrieves a list of tool bar items to display at the top of the tool.
		do
		end

feature -- Properties

	filter_enabled: BOOLEAN
			-- Is filtering enabled ?

	filter: ARRAY [STRING_32]
			-- Filter tags

	filter_command: EB_STANDARD_CMD
			-- Filtering command

feature -- Widgets

	filter_bar: EV_HORIZONTAL_BOX
			-- Filter bar

	grid: ES_IDE_GRID
			-- Grid containing the breakpoints list.

	grid_wrapper: EVS_GRID_WRAPPER [EV_GRID_ROW]
			-- Wrapper on `grid'
		require
			is_initialized: is_initialized
			not_is_recycled: not is_recycled
		do
			Result := internal_grid_wrapper
			if Result = Void then
				create Result.make (grid)
				internal_grid_wrapper := Result
			end
		ensure
			result_attached: Result /= Void
			result_consistent: Result = grid_wrapper
		end

	enable_bkpt_button: EB_SD_COMMAND_TOOL_BAR_BUTTON
			-- Enable breakpoint button

	disable_bkpt_button: EB_SD_COMMAND_TOOL_BAR_BUTTON
			-- Disable breakpoint button

	clear_bkpt_button: EB_SD_COMMAND_TOOL_BAR_BUTTON
			-- Clear breakpoint button

feature {NONE} -- Sort handling

	enable_sorting
			-- Enables sorting on `grid' for specific columns
		require
			not_is_recycled: not is_recycled
		local
			l_wrapper: like grid_wrapper
			l_sort2_info: EVS_GRID_TWO_WAY_SORTING_INFO [EV_GRID_ROW]
			l_sort3_info: EVS_GRID_THREE_WAY_SORTING_INFO [EV_GRID_ROW]
			l_column: EV_GRID_COLUMN
		do
			l_wrapper := grid_wrapper
			l_wrapper.enable_auto_sort_order_change
			if l_wrapper.sort_action = Void then
				l_wrapper.set_sort_action (agent sort_handler)
			end

				--| Data column
			l_column := grid.column (Data_column_index); check l_column /= Void end
				-- Set fake sorting routine as sorting is handled in `sort_handler'
			create l_sort3_info.make (agent (a_row, a_other_row: EV_GRID_ROW; a_order: INTEGER_32): BOOLEAN do Result := False end, {EVS_GRID_TWO_WAY_SORTING_ORDER}.topology_order)
			l_sort3_info.enable_auto_indicator
			l_wrapper.set_sort_info (l_column.index, l_sort3_info)

				--| Status column
			l_column := grid.column (Status_column_index); check l_column /= Void end
				-- Set fake sorting routine as sorting is handled in `sort_handler'
			create l_sort2_info.make (agent (a_row, a_other_row: EV_GRID_ROW; a_order: INTEGER_32): BOOLEAN do Result := False end, {EVS_GRID_TWO_WAY_SORTING_ORDER}.descending_order)
			l_sort2_info.enable_auto_indicator
			l_wrapper.set_sort_info (l_column.index, l_sort2_info)

				--| Tags column
			l_column := grid.column (Tags_column_index); check l_column /= Void end
				-- Set fake sorting routine as sorting is handled in `sort_handler'
			create l_sort2_info.make (agent (a_row, a_other_row: EV_GRID_ROW; a_order: INTEGER_32): BOOLEAN do Result := False end, {EVS_GRID_TWO_WAY_SORTING_ORDER}.descending_order)
			l_sort2_info.enable_auto_indicator
			l_wrapper.set_sort_info (l_column.index, l_sort2_info)
		end

	disable_sorting
			-- Disable sorting
		local
			l_wrapper: like grid_wrapper
		do
			l_wrapper := internal_grid_wrapper
			if l_wrapper /= Void then
				l_wrapper.wipe_out_sorted_columns
				l_wrapper.disable_auto_sort_order_change
				l_wrapper.set_sort_action (Void)
				internal_grid_wrapper := Void
			end
		end

	sort_handler (a_column_list: LIST [INTEGER]; a_comparator: AGENT_LIST_COMPARATOR [EV_GRID_ROW])
			-- Action to be performed when sort `a_column_list' using `a_comparator'.
		require
			a_column_list_attached: a_column_list /= Void
			not_a_column_list_is_empty: not a_column_list.is_empty
			a_comparator_attached: a_comparator /= Void
		do
			if attached develop_window_session_data as w_session_data then
					-- Set session data
				w_session_data.set_value (grid_wrapper.string_representation_of_sorted_columns, columns_sorting_data_session_id)
			end

				-- Repopulate grid
			execute_with_busy_cursor (agent
				do
					refresh_breakpoints_info
				end)
		end

feature -- Events

	on_filter_clicked
		do
			if filter_enabled then
				filter_enabled := False
				filter := Void
				filter_bar.hide
				refresh_breakpoints_info
			else
				filter_enabled := True
				filter_bar.show
			end
		end

	on_stone_dropped (a_stone: STONE)
			--	Stone dropped.
		local
			bm: BREAKPOINTS_MANAGER
		do
			bm := debugger_manager.breakpoints_manager
			if attached {FEATURE_STONE} a_stone as fs then
				if not bm.is_breakpoint_set (fs.e_feature, 1, False) then
					bm.enable_first_user_breakpoint_of_feature (fs.e_feature)
					bm.notify_breakpoints_changes
				end
			elseif attached {CLASSC_STONE} a_stone as cs then
				bm.enable_first_user_breakpoints_in_class (cs.e_class)
				bm.notify_breakpoints_changes
			end
		end

	on_item_pebble_function (gi: EV_GRID_ITEM): detachable STONE
			-- Handle item pebble function.
		do
			if gi /= Void then
				if attached {ES_GRID_BREAKPOINT_LOCATION_ITEM} gi as bpl then
					Result := bpl.pebble_at_position
				elseif attached {STONE} gi.data as s then
					Result := s
				end
			end
		end

	on_item_pebble_accept_cursor (gi: EV_GRID_ITEM): EV_POINTER_STYLE
			-- Handle item pebble accpet cursor
		do
			if attached on_item_pebble_function (gi) as st then
				Result := st.stone_cursor
			end
		end

	on_item_pebble_deny_cursor (gi: EV_GRID_ITEM): EV_POINTER_STYLE
			-- Handle item pebble deny cursor
		do
			if attached on_item_pebble_function (gi) as st then
				Result := st.x_stone_cursor
			end
		end

feature -- Updating

	update
			-- Refresh `Current's display.
		do
			grid.request_delayed_clean
			refresh_breakpoints_info
		end

	refresh
			-- Class has changed in `development_window'.
		local
			r: INTEGER
			g: like grid
			l_row: EV_GRID_ROW
		do
			if is_initialized and is_shown then
				g := grid
				if g.row_count = 0 then
					update
				else
					from
						r := g.row_count
					until
						r = 0
					loop
						l_row := g.row (r)
						if attached {BREAKPOINT} l_row.data as bp then
							l_row.clear
						end
						r := r - 1
					end
				end
			end
		end

	synchronize
			-- Synchronize
		do
			if is_initialized then
				update
			end
		end

	on_project_loaded
			-- Handle project loaded actions
		do
			if is_initialized then
				update
			end
		end

feature {NONE} -- Action handlers

	on_show
			-- Performs actions when the user widget is displayed.
		do
			Precursor
			if is_initialized then
				if grid.is_displayed and grid.is_sensitive then
					grid.set_focus
				end
				refresh
			end
		end

feature -- Memory management

	internal_recycle
			-- Recycle `Current', but leave `Current' in an unstable state,
			-- so that we know whether we're still referenced or not.
		do
			if is_initialized then
				enable_bkpt_button.recycle
				disable_bkpt_button.recycle
				clear_bkpt_button.recycle
			end
			Preferences.debug_tool_data.row_highlight_background_color_preference.change_actions.prune_all (set_row_highlight_bg_color_agent)
			set_row_highlight_bg_color_agent := Void
			Precursor {ES_DOCKABLE_TOOL_PANEL}
		end

feature {NONE} -- Grid layout Implementation

	grid_layout_manager: ES_GRID_LAYOUT_MANAGER
			-- Grid layout manager

	record_grid_layout
			-- Record grid layout
		do
			if grid_layout_manager = Void then
				create grid_layout_manager.make (grid, "Breakpoints")
			end
			grid_layout_manager.record
		end

	restore_grid_layout
			-- Restore grid layout
		do
			if grid_layout_manager /= Void then
				grid_layout_manager.restore
			end
		end

feature {NONE} -- Implementation

	clean_breakpoints_info
			-- Clean the breakpoints's grid
		do
			record_grid_layout
			grid.default_clean
		end

	refresh_breakpoints_info
			-- Refresh and recomputed breakpoints's grid when shown
		do
			if is_shown then -- Tool exists in layout and is displayed
				refresh_breakpoints_info_now
			else
				request_refresh_breakpoints_info_now
			end
		end

feature {NONE} -- Refresh breakpoints info Now implementation

	agent_refresh_breakpoints_info_now: PROCEDURE
			-- agent on `refresh_breakpoints_info_now'.

	request_refresh_breakpoints_info_now
			-- Request `refresh_breakpoints_info_now'
		require
			tool_visible: content /= Void
		do
			if agent_refresh_breakpoints_info_now = Void then
				agent_refresh_breakpoints_info_now := agent refresh_breakpoints_info_now
				content.show_actions.extend_kamikaze (agent_refresh_breakpoints_info_now)
			else
				-- already requested
			end
		end

	cancel_refresh_breakpoints_info_now
			-- Request `refresh_breakpoints_info_now'
		do
			if agent_refresh_breakpoints_info_now /= Void then
				if content /= Void then
					content.show_actions.prune_all (agent_refresh_breakpoints_info_now)
				end
				agent_refresh_breakpoints_info_now := Void
			end
		end

	refresh_breakpoints_info_now
			-- Refresh and recomputed breakpoints's grid
		require
			content_widget_visible: content /= Void and then content.user_widget /= Void and then content.user_widget.is_show_requested
		do
			cancel_refresh_breakpoints_info_now

			class_color := preferences.editor_data.class_text_color
			feature_color := preferences.editor_data.feature_text_color
			condition_color := preferences.editor_data.string_text_color

			populate_grid
		end

feature {NONE} -- Impl filling

	populate_grid
			-- Fetch data and Populate breakpoints's grid.
		local
			col: EV_COLOR
			bpm: BREAKPOINTS_MANAGER
			lab: EV_GRID_LABEL_ITEM
			f_list: LIST [E_FEATURE]
			l_last_sort_column: INTEGER
			l_last_sort_order: INTEGER
			bplst: BREAK_LIST
			bps: ARRAYED_LIST [BREAKPOINT]
			bp: BREAKPOINT
			no_bp: BOOLEAN
			l_filter: like filter
		do
			if is_initialized then
				l_last_sort_column := grid_wrapper.last_sorted_column
				if l_last_sort_column > 0 then
					l_last_sort_order := grid_wrapper.column_sort_info.item (l_last_sort_column).current_order
				end
			end
			if l_last_sort_column = 0 then
				l_last_sort_column := data_column_index
				l_last_sort_order := {EVS_GRID_TWO_WAY_SORTING_ORDER}.topology_order
			end

			grid.call_delayed_clean --| Clean grid right now
			col := preferences.editor_data.comments_text_color
			bpm := Debugger_manager.breakpoints_manager

			if filter_enabled then
				l_filter := filter
				if l_filter /= Void and then l_filter.is_empty then
					l_filter := Void
				end
			end

			if l_last_sort_order = {EVS_GRID_TWO_WAY_SORTING_ORDER}.topology_order	then
				check data_column_selected: l_last_sort_column = Data_column_index end

				if bpm.has_set_and_valid_breakpoint then
					if l_filter /= Void then
						f_list := bpm.features_associated_to (bpm.user_breakpoints_tagged (l_filter))
					else
						f_list := bpm.features_associated_to (bpm.user_breakpoints_set)
					end

						-- Tree like grid
					grid.enable_tree
					insert_bp_features_list (f_list)
				else
					no_bp := True
				end
			else
					-- Flat like grid
				bplst := bpm.breakpoints
				from
					create bps.make (bplst.count)
					bps.compare_objects
					bplst.start
				until
					bplst.after
				loop
					bp := bplst.item_for_iteration
					if bp /= Void and then bp.is_set then
						if l_filter = Void or else bp.match_tags (l_filter) then
							bps.force (bp)
						end
					end
					bplst.forth
				end

				no_bp := bps.is_empty
				if not no_bp then
					(create {QUICK_SORTER [BREAKPOINT]}.make (
								create {AGENT_EQUALITY_TESTER [BREAKPOINT]}.make (
										agent (a_data, a_other_data: BREAKPOINT; a_column, a_order: INTEGER): BOOLEAN
											local
												s1,s2: STRING_32
											do
												inspect a_column
												when Data_column_index then
													Result := a_data.location.is_lesser_than (a_other_data.location)
												when Status_column_index then
													if a_data.is_enabled = a_other_data.is_enabled then
														Result := a_data.location.is_lesser_than (a_other_data.location)
													elseif a_data.is_enabled then
														Result := True
													else
														Result := False
													end
												when Tags_column_index then
													s1 := a_data.tags_as_string
													s2 := a_other_data.tags_as_string
													if s1.is_equal (s2) then
														Result := a_data.location.is_lesser_than (a_other_data.location)
													else
														Result := s1 < s2
													end
												end
												if a_order = {EVS_GRID_TWO_WAY_SORTING_ORDER}.descending_order then
													Result := not Result
												end
											end (?, ?, l_last_sort_column, l_last_sort_order)
										)
								)
						).sort(bps)

					grid.disable_tree
					insert_bp_list (bps)
				end
			end

			if no_bp then
				grid.insert_new_row (1)
				create lab.make_with_text (interface_names.l_no_break_point)
				lab.set_foreground_color (col)
				grid.set_item (1, 1, lab)
			end

			debug("breakpoint")
				insert_metrics
			end
			grid.request_columns_auto_resizing
			restore_grid_layout
		end

	insert_bp_list (bps: LIST [BREAKPOINT])
		require
			not grid.is_tree_enabled
		local
			r: INTEGER
		do
			from
				r := 1
				grid.insert_new_rows (bps.count, r)
				bps.start
			until
				bps.after
			loop
				grid.row (r).set_data (bps.item_for_iteration)
				r := r + 1
				bps.forth
			end
		end

	insert_bp_features_list (routine_list: LIST [E_FEATURE])
			-- Insert `routine_list' into `a_row'
		require
			routine_list /= Void
			grid.is_tree_enabled
		local
			r, sr: INTEGER
			lab: EV_GRID_LABEL_ITEM
			subrow: EV_GRID_ROW

			table: HASH_TABLE [PART_SORTED_TWO_WAY_LIST [E_FEATURE], INTEGER]
			stwl: PART_SORTED_TWO_WAY_LIST [E_FEATURE]
			f: E_FEATURE
			c: CLASS_C
			has_bp: BOOLEAN
			bpm: BREAKPOINTS_MANAGER
		do
				--| Prepare data .. mainly sorting
			from
				create table.make (5)
				routine_list.start
			until
				routine_list.after
			loop
				f := routine_list.item
				c := f.written_class
				stwl := table.item (c.class_id)
				if stwl = Void then
					create stwl.make
					table.put (stwl, c.class_id)
				end
				stwl.extend (f)
				routine_list.forth
			end

				--| Process insertion
			bpm := Debugger_manager.breakpoints_manager
			from
				table.start
				r := 1
			until
				table.after
			loop
				stwl := table.item_for_iteration
				c := Eiffel_system.class_of_id (table.key_for_iteration)
				has_bp := False
					--| Check if there are any valid and displayable breakpoints
				from
					stwl.start
				until
					stwl.after or has_bp
				loop
					f := stwl.item
					if bpm.is_feature_breakable (f) then
						has_bp := not bpm.breakpoints_set_for (f, False).is_empty
					end
					stwl.forth
				end

				if has_bp then
					create lab.make_with_text (c.name_in_upper)
					lab.set_foreground_color (class_color)
					lab.set_data (create {CLASSC_STONE}.make (c))

					r := grid.row_count + 1
					grid.insert_new_row (r)
					subrow := grid.row (r)

					sr := 1
					subrow.set_item (Data_column_index, lab)
					subrow.set_item (Status_column_index, create {EV_GRID_ITEM})
					subrow.item (Status_column_index).pointer_button_release_actions.extend (agent on_class_item_right_clicked (c, subrow, ?, ?, ?, ?, ?, ?, ?, ?))

					from
						stwl.start
					until
						stwl.after
					loop
						f := stwl.item
						insert_feature_bp_detail (f, subrow)
						stwl.forth
					end
					if subrow.is_expandable then
						subrow.expand
					end
				end
				table.forth
			end
		end

	insert_feature_bp_detail (f: E_FEATURE; a_row: EV_GRID_ROW)
			-- Insert features breakpoints details.
		require
			f_not_void: f /= Void
			a_row_not_void: a_row /= Void
		local
			bp_list: LIST [INTEGER]
			sorted_bp_list: SORTED_TWO_WAY_LIST [INTEGER]
			s: STRING
			ir, sr: INTEGER
			subrow: EV_GRID_ROW
			lab: EV_GRID_LABEL_ITEM
			first_bp: BOOLEAN
			i: INTEGER
			bp: BREAKPOINT
			bpm: BREAKPOINTS_MANAGER
			loc: BREAKPOINT_LOCATION
			l_filter: like filter
		do
			bpm := Debugger_manager.breakpoints_manager
			bp_list := bpm.breakpoints_set_for (f, False)
			if not bp_list.is_empty then
				sr := a_row.subrow_count + 1
				a_row.insert_subrow (sr)
				subrow := a_row.subrow (sr)

				create lab.make_with_text (f.name_32)
				lab.set_foreground_color (feature_color)
				lab.set_data (create {FEATURE_STONE}.make (f))

				if filter_enabled then
					l_filter := filter
					if l_filter /= Void and then l_filter.is_empty then
						l_filter := Void
					end
				end

				subrow.set_item (Data_column_index, lab)
				from
					s := ""
					first_bp := True
					create sorted_bp_list.make
					sorted_bp_list.fill (bp_list)
					bp_list := sorted_bp_list
					bp_list.start
					ir := 1
				until
					bp_list.after
				loop
					i := bp_list.item
					loc := bpm.breakpoint_location (f, i, False)
					if bpm.is_user_breakpoint_set_at (loc) then
						bp := bpm.user_breakpoint_at (loc)
						if l_filter = Void or else bp.match_tags (l_filter) then
							if not first_bp then
								s.append_string (", ")
							else
								first_bp := False
							end
							s.append_string (i.out)
							subrow.insert_subrow (ir)
							subrow.subrow (ir).set_data (bp)
							ir := ir + 1
							if bp.has_condition then
								if bp.is_disabled then
									s.append_string (Disabled_conditional_bp_symbol)
								else
									s.append_string (Conditional_bp_symbol)
								end
							elseif bp.is_disabled then
								s.append_string (Disabled_bp_symbol)
							end
						end
					elseif bpm.is_hidden_breakpoint_set_at (loc) then
						--| hidden breakpoint .. so keep it hidden ;)
					else
						create lab.make_with_text (interface_names.l_error_with_line (f.name_32, i.out))
						subrow.insert_subrow (ir)
						subrow.subrow (ir).set_item (Status_column_index, lab)
						ir := ir + 1
					end
					bp_list.forth
				end
				create lab.make_with_text (s)
				subrow.set_item (Status_column_index, lab)
				lab.pointer_button_release_actions.extend (agent on_feature_item_right_clicked (f, subrow, ?, ?, ?, ?, ?, ?, ?, ?))
				subrow.ensure_expandable
				if subrow.is_expandable then
					subrow.expand
				end
			end
		end

	insert_metrics
		local
			t: TUPLE [total: INTEGER; not_set: INTEGER; enabled: INTEGER; hidden_enabled: INTEGER; disabled: INTEGER; hidden_disabled: INTEGER]
			splab: EV_GRID_SPAN_LABEL_ITEM
			s: STRING
			i: INTEGER
		do
			debug("breakpoint")
				t := breakpoints_manager.metrics
				if t /= Void then
					s := ""
					s.append_string ("total=" + t.total.out)
					if t.not_set > 0 then
						s.append_string (", not_set=" + t.not_set.out)
					end
					if t.enabled > 0 then
						s.append_string (", enabled=" + t.enabled.out)
					end
					if t.hidden_enabled > 0 then
						s.append_string (", hidden_enabled=" + t.hidden_enabled.out)
					end
					if t.disabled > 0 then
						s.append_string (", disabled=" + t.disabled.out)
					end
					if t.hidden_disabled > 0 then
						s.append_string (", hidden_disabled=" + t.hidden_disabled.out)
					end

					create {EV_GRID_SPAN_LABEL_ITEM} splab.make_master (1)
					grid.insert_new_row (grid.row_count + 1)
					grid.row (grid.row_count).set_background_color (grid.foreground_color)
					grid.row (grid.row_count).set_foreground_color (grid.background_color)
					splab.set_text (s)

					grid.set_item (splab.span_master_column, grid.row_count, splab)
					from
						i := splab.span_master_column + 1
					until
						i > 4
					loop
						grid.set_item (i, grid.row_count, create {EV_GRID_SPAN_LABEL_ITEM}.make_span (1))
						i := i + 1
					end
				end
				print ("%N---%N")
				print ("breakpoints.count=" + breakpoints_manager.breakpoints.count.out + "%N")
				breakpoints_manager.breakpoints.linear_representation.do_all (agent (abp: BREAKPOINT)
						do
							localized_print (abp.string_representation (True) + "%N")
						end
					)
			end
		end



feature {NONE} -- Dynamic item filling

	computed_grid_item (c, r: INTEGER): EV_GRID_ITEM
			-- Computed grid item corresponding to `c,r'.
		local
			row: EV_GRID_ROW
			i,n: INTEGER
		do
			row := grid.row (r)
			compute_bp_row (row)

				--| fill_empty_cells of `row'
			n := row.parent.column_count
			from
				i := 1
			until
				i > n
			loop
				if row.item (i) = Void then
					row.set_item (i, create {EV_GRID_ITEM})
				end
				i := i + 1
			end

				--| Now Result should not be Void
			Result := row.item (c)
			if Result = Void then
				create Result
			end
		end

	compute_bp_row (a_row: EV_GRID_ROW)
			-- Compute `a_row' 's grid items
		require
			a_row_not_void: a_row /= Void
		local
			f: E_FEATURE
			s: STRING_32
			t: STRING_32
			cell: EV_GRID_ITEM
			lab: EV_GRID_LABEL_ITEM
			bploc_item: ES_GRID_BREAKPOINT_LOCATION_ITEM
			i: INTEGER
			fs: FEATURE_STONE
		do
			if attached {BREAKPOINT} a_row.data as bp and then not bp.is_corrupted then
				f := bp.routine
				i := bp.breakable_line_number

					--| Data
				if grid.is_tree_enabled then
					create lab.make_with_text (interface_names.l_offset_is (i.out))
					create fs.make (f)
					lab.set_data (fs)

					cell := lab
				else
					create bploc_item.make (bp.location)

					create fs.make (f)
					bploc_item.set_data (fs)

					cell := bploc_item
				end
				a_row.set_item (Data_column_index, cell)

					--| Status
				if bp.is_enabled then
					s := interface_names.l_space_enabled.twin
					if bp.hits_count > 0 then
						s.append (" (")
						s.append (interface_names.l_hit_count_is (bp.hits_count))
						s.append (")")
					end
					create lab.make_with_text (s)
					if bp.has_condition then
						lab.set_pixmap (breakable_icons.bp_enabled_conditional_icon)
					else
						lab.set_pixmap (breakable_icons.bp_enabled_icon)
					end
				elseif bp.is_disabled then
					create lab.make_with_text (interface_names.l_space_disabled)
					if bp.has_condition then
						lab.set_pixmap (breakable_icons.bp_disabled_conditional_icon)
					else
						lab.set_pixmap (breakable_icons.bp_disabled_icon)
					end
				else
					create lab.make_with_text (interface_names.l_space_error)
				end
				debug ("breakpoint")
					t := bp.routine.associated_class.name_in_upper + "."
					t.append (bp.routine.name_32)
					t.append ("#" + bp.breakable_line_number.out)
					if debugger_manager.application_is_executing then
						if bp.location.is_set_for_application then
							t.append_string ("Application: set")
						else
							t.append_string ("Application: not set")
						end
					end
					if bp.has_tags then
						t.append_character ('%N')
						t.append_string_general ("Tags: ")
						bp.tags.do_all (agent (atag: STRING_32; astr: STRING_32)
								do
									if atag /= Void then
										astr.append (atag + ", ")
									end
								end(?, t)
							)
					end
					if bp.hits_count > 0 then
						t.append_character ('%N')
						t.append_string_general (Interface_names.l_current_hit_count)
						t.append_integer (bp.hits_count)
					end
					if bp.has_condition then
						t.append_character ('%N')
						t.append_string_general (interface_names.l_condition)
						t.append_string (": " + bp.condition.text)
					end
					if bp.has_when_hits_action then
						t.append_character ('%N')
						t.append_string_general (interface_names.m_when_hits)
						bp.when_hits_actions.do_all (agent (ai: BREAKPOINT_WHEN_HITS_ACTION_I; astr: STRING_32)
								do
									astr.append_string (ai.generating_type.name_32 + {STRING_32} ", ")
								end(?, t)
							)
					end
					if bp.continue_execution then
						t.append_character ('%N')
						t.append_string_general (interface_names.l_continue_execution)
					end
					lab.set_tooltip (t)
				end

				lab.pointer_double_press_actions.extend (agent on_breakpoint_cell_double_left_clicked (f, i, lab, ?, ?, ?, ?, ?, ?, ?, ?))
				lab.pointer_button_release_actions.extend (agent on_line_cell_right_clicked (f, i, lab, ?, ?, ?, ?, ?, ?, ?, ?))
				a_row.set_item (Status_column_index, lab)

				if bp.has_condition then
					create lab.make_with_text (bp.condition.text)
					lab.set_tooltip (lab.text)
					lab.set_font (condition_font)
					a_row.set_item (Details_column_index, lab)
				end
				if bp.has_tags then
					create lab.make_with_text (bp.tags_as_string)
					lab.set_tooltip (lab.text)
					a_row.set_item (Tags_column_index, lab)
				end
				if bp.is_hidden then
					a_row.set_background_color ((create {EV_STOCK_COLORS}).red)
				end
			end
		end

feature {NONE} -- Events on grid

	on_breakpoint_cell_double_left_clicked (f: E_FEATURE; i: INTEGER; gi: EV_GRID_ITEM; x, y, button: INTEGER; tx, ty, p: REAL_64; sx, sy: INTEGER)
			-- Handle a cell right click actions.
		require
			f /= Void
			i > 0
			gi /= Void
		local
			bp_stone: BREAKABLE_STONE
		do
			grid.remove_selection
			gi.row.enable_select
			if button = 1 then
				create bp_stone.make (f, i)
				bp_stone.open_breakpoint_dialog
			end
		end

	on_line_cell_right_clicked (f: E_FEATURE; i: INTEGER; gi: EV_GRID_ITEM; x, y, button: INTEGER; tx, ty, p: REAL_64; sx, sy: INTEGER)
			-- Handle a cell right click actions.
		require
			f /= Void
			i > 0
			gi /= Void
		local
			bp_stone: BREAKABLE_STONE
		do
			grid.remove_selection
			gi.row.enable_select
			if button = 3 then
				create bp_stone.make (f, i)
				bp_stone.display_bkpt_menu
			end
		end

	on_class_item_right_clicked	(c: CLASS_C; r: EV_GRID_ROW; x, y, button: INTEGER; tx, ty, p: REAL_64; sx, sy: INTEGER)
		require
			c /= Void
			r /= Void
		local
			m: EV_MENU
			mi: EV_MENU_ITEM
			bpm: BREAKPOINTS_MANAGER
		do
			grid.remove_selection
			r.enable_select
			if button = 3 then
				bpm := Debugger_manager.breakpoints_manager
				create m
				create mi.make_with_text (interface_names.m_add_first_breakpoints_in_class)
				mi.select_actions.extend (agent bpm.enable_first_user_breakpoints_in_class (c))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				create mi.make_with_text (Interface_names.m_enable_stop_points)
				mi.select_actions.extend (agent bpm.enable_user_breakpoints_in_class (c))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				create mi.make_with_text (Interface_names.m_disable_stop_points)
				mi.select_actions.extend (agent bpm.disable_user_breakpoints_in_class (c))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				create mi.make_with_text (Interface_names.m_clear_breakpoints)
				mi.select_actions.extend (agent bpm.remove_user_breakpoints_in_class (c))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				m.show
			end
		end

	on_feature_item_right_clicked	(f: E_FEATURE; r: EV_GRID_ROW; x, y, button: INTEGER; tx, ty, p: REAL_64; sx, sy: INTEGER)
		require
			f /= Void
			r /= Void
		local
			m: EV_MENU
			mi: EV_MENU_ITEM
			bpm: BREAKPOINTS_MANAGER
		do
			grid.remove_selection
			r.enable_select
			if button = 3 then
				bpm := Debugger_manager.breakpoints_manager
				create m
				create mi.make_with_text (interface_names.m_add_first_breakpoints_in_feature)
				mi.select_actions.extend (agent bpm.enable_first_user_breakpoint_of_feature (f))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				create mi.make_with_text (Interface_names.m_enable_stop_points)
				mi.select_actions.extend (agent bpm.enable_user_breakpoints_in_feature (f))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				create mi.make_with_text (Interface_names.m_disable_stop_points)
				mi.select_actions.extend (agent bpm.disable_user_breakpoints_in_feature (f))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)
				m.extend (mi)
				create mi.make_with_text (Interface_names.m_clear_breakpoints)
				mi.select_actions.extend (agent bpm.remove_user_breakpoints_in_feature (f))
				mi.select_actions.extend (agent window_manager.synchronize_all_about_breakpoints)

				m.extend (mi)
				m.show
			end
		end

	key_pressed_on_grid (a_key: EV_KEY)
			-- Key events on grid's handler
		local
			g: like grid
			l_selected_rows: LIST [EV_GRID_ROW]
			l_row_indexes: ARRAYED_LIST [INTEGER]
			l_row: EV_GRID_ROW
			bp_stone: BREAKABLE_STONE
			bp_changed: BOOLEAN
			l_unprocessed: BOOLEAN
		do
			g := grid
			if ev_application.ctrl_pressed then
				if a_key.code = {EV_KEY_CONSTANTS}.key_a then
					g.remove_selection
					g.select_all_rows
				end
			else
				if g.has_selected_row then
					l_selected_rows := g.selected_rows
					inspect a_key.code
					when {EV_KEY_CONSTANTS}.key_space then
						from
							l_selected_rows.start
						until
							l_selected_rows.after
						loop
							l_row := l_selected_rows.item
							if attached {BREAKPOINT} l_row.data as bp_s then
								if bp_s.is_enabled then
									bp_s.disable
								else
									bp_s.enable
								end
								bp_changed := True
								l_selected_rows.item.clear  --| refresh the related grid items
							end
							l_selected_rows.forth
						end
					when {EV_KEY_CONSTANTS}.key_delete then
						from
							l_selected_rows.start
						until
							l_selected_rows.after
						loop
							l_row := l_selected_rows.item
							if attached {BREAKPOINT} l_row.data as bp_d then
								l_selected_rows.remove
								bp_d.discard
								bp_changed := True
								g.remove_row (l_row.index)
							else
								l_selected_rows.forth
							end
						end
						l_selected_rows := Void
					when {EV_KEY_CONSTANTS}.key_enter then
						if attached {BREAKPOINT} l_selected_rows.first.data as bp_e then
							create bp_stone.make_from_breakpoint (bp_e)
							bp_stone.display_bkpt_menu
						end
						l_row := l_selected_rows.first
					else
						l_unprocessed := True
					end
					if not l_unprocessed then
						g.remove_selection
						if l_selected_rows /= Void and then l_selected_rows.count > 0 then
							create l_row_indexes.make (l_selected_rows.count)
							from
								l_selected_rows.start
							until
								l_selected_rows.after
							loop
								l_row := l_selected_rows.item_for_iteration
								if l_row /= Void and then l_row.parent /= Void then
									l_row_indexes.extend (l_row.index)
								end
								l_selected_rows.forth
							end
						end
						if bp_changed then
							breakpoints_manager.notify_breakpoints_changes
						end
						if l_row_indexes /= Void and then l_row_indexes.count > 0 then
							l_row_indexes.do_all (agent (r: INTEGER; ag: like grid)
									do
										if r > 0 and r <= ag.row_count then
											ag.row (r).enable_select
										end
									end (?, g)
								)
						end
					end
				end
			end
		end

feature {NONE} -- Internal implementation cache

	internal_grid_wrapper: like grid_wrapper
			-- Cached version of `grid_wrapper'
			-- Note: do not use directly!

feature {NONE} -- Grid columns' Constants

	Data_column_index: INTEGER = 1
	Status_column_index: INTEGER = 2
	Details_column_index: INTEGER = 3
	Tags_column_index: INTEGER = 4

feature {NONE} -- Constants

	columns_sorting_data_session_id: STRING_8 = "com.eiffel.breakpoints_tool.columns_sorting_data"
			-- Session id to store columns sorting data

feature {NONE} -- Implementation, cosmetic

	Disabled_bp_symbol: STRING = "-"
			-- Disable breakpoint symbol.

	Conditional_bp_symbol: STRING = "*"
			-- Conditional breakpoint symbol.

	Disabled_conditional_bp_symbol: STRING = "*-"
			-- Disable conditional breakpoint symbol.

	Breakable_icons: ES_SMALL_ICONS
			-- Breakable icons.
		do
				-- TODO review
				-- update once feature to load pixmaps based monitor dpi.
				-- using object-less call
				-- Date: 05/24/2019
			Result := {EB_SHARED_PIXMAPS}.small_pixmaps
		ensure
			result_attached: Result /= Void
		end

	bg_separator_color: EV_COLOR
			-- Background separator color.
		once
			create Result.make_with_8_bit_rgb (220, 220, 240)
		end

	class_color: EV_COLOR
			-- Class color
	feature_color: EV_COLOR
			-- Feature color
	condition_color: EV_COLOR
			-- Condition color
	condition_font: EV_FONT
			-- Condition font
		once
			create Result
			Result.set_shape ({EV_FONT_CONSTANTS}.shape_italic)
		end

	set_row_highlight_bg_color_agent : PROCEDURE
			-- Set row highlight background color agent.

	set_row_highlight_bg_color (v: COLOR_PREFERENCE)
			-- Set row highlight background color.
		do
			row_highlight_bg_color := v.value
		end

	row_highlight_bg_color: EV_COLOR;
			-- Row highlight background color.

note
	copyright: "Copyright (c) 1984-2021, Eiffel Software"
	license:   "GPL version 2 (see http://www.eiffel.com/licensing/gpl.txt)"
	licensing_options: "http://www.eiffel.com/licensing"
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
