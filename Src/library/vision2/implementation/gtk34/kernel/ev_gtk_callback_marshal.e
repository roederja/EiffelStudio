note
	description: "Callback Marshal to deal with gtk signal emissions"
	legal: "See notice at end of class."
	status: "See notice at end of class."
	date: "$Date$"
	revision: "$Revision$"

class
	EV_GTK_CALLBACK_MARSHAL

inherit

	IDENTIFIED
		undefine
			default_create,
			copy,
			is_equal
		end

	EV_INTERMEDIARY_ROUTINES
		undefine
			default_create
		end

	EXCEPTIONS
		export
			{NONE} all
		undefine
			default_create
		end

create
	default_create


feature {NONE} -- Initialization

	default_create
			-- Create the dispatcher, one object per system.
		do
			initialize
		end

	initialize
			-- Initialize callbacks
		once
			c_ev_gtk_callback_marshal_init ($Current, $marshal)
			c_ev_gtk_callback_marshal_set_is_enabled (True)
		end

feature {EV_ANY_IMP} -- Access

	translate_and_call (
		an_agent: ROUTINE;
		translate: FUNCTION [INTEGER, POINTER, TUPLE];
	): detachable ANY
			-- Call `an_agent' using `translate' to convert `args' and `n_args'
		require
			an_agent_not_void: an_agent /= Void
			translate_not_void: translate /= Void
		do
			if attached {FUNCTION [TUPLE, detachable ANY]} an_agent as fct then
				Result := fct.item (translate.item (integer_pointer_tuple))
			else
				an_agent.call (translate.item (integer_pointer_tuple))
			end
		end

	dimension_tuple (a_x, a_y, a_width, a_height: INTEGER): like internal_dimension_tuple
			-- Return a dimension tuple from given arguments.
		do
			Result := internal_dimension_tuple
			Result.x := a_x
			Result.y := a_y
			Result.width := a_width
			Result.height := a_height
		end

	key_tuple (a_key: EV_KEY; a_key_string: STRING_32; a_key_press: BOOLEAN): like internal_key_tuple
			-- Return a key tuple from given arguments.
		do
			Result := internal_key_tuple
			Result.key := a_key
			Result.string := a_key_string
			Result.key_press := a_key_press
		end

feature -- Implementation

	signal_connect (
					a_c_object: POINTER;
					a_signal_name: EV_GTK_C_STRING;
					an_agent: ROUTINE;
					translate: detachable FUNCTION [INTEGER, POINTER, TUPLE];
					invoke_after_handler: BOOLEAN
				)
			-- Signal connect, depending on `invoke_after_handler` invoked before or after default handler.
			-- Notes:
			--		- on connect the agent `an_agent` is eif_adopt-ed by the run-time
			--		- on disconnect the eif_adopt-ed agent `an_agent` is eif_wean-ed by the run-time
			--			and thus can be collected by the GC
		local
			l_agent: ROUTINE
			l_conn_id: like last_signal_connection_id
		do
			if translate = Void then
					-- If we have no translate agent then we call the agent directly.
				l_agent := an_agent
			else
				l_agent := agent translate_and_call (an_agent, translate)
			end

			l_conn_id := {EV_GTK_CALLBACK_MARSHAL}.c_signal_connect (
				a_c_object,
				a_signal_name.item,
				l_agent,
				invoke_after_handler
			)
			last_signal_connection_id := l_conn_id
			debug("gtk_signal")
				print (generator + ".signal_connect ("
							+ a_c_object.out +", "
							+ a_signal_name.string.to_string_8 + ", "
							+ if attached an_agent.target as tgt then tgt.generator else "NoTarget" end
							+ " ...,"+ invoke_after_handler.out +") -> "+ last_signal_connection_id.out +"%N")
			end
		end

	signal_connect_after (
					a_c_object: POINTER;
					a_signal_name: EV_GTK_C_STRING;
					an_agent: ROUTINE;
					translate: detachable FUNCTION [INTEGER, POINTER, TUPLE]
				)
			-- Signal connect, invoke after default handler.
		do
			signal_connect (a_c_object, a_signal_name, an_agent, translate, True)
		end

	signal_disconnect (a_c_object: POINTER; a_conn_id: INTEGER)
			-- Close connection `a_conn_id` for object `a_c_object`.
			-- Note: the associated Eiffel agent will be "wean" by the run-time
		do
			{GTK2}.signal_disconnect (a_c_object, a_conn_id)
		end

	last_signal_connection_id: INTEGER
			-- Last signal connection id.

feature -- Agent functions.

	set_focus_event_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for set-focus events
		once
			Result :=
			agent (n: INTEGER; p: POINTER): TUPLE
					-- Converted GtkWidget* to tuple.
				do
					Result := [{GTK2}.gtk_value_pointer (p)]
				end
		end

	size_allocate_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for size allocation events
		once
			Result :=
			agent (n: INTEGER; p: POINTER): TUPLE
				local
					gtk_alloc: POINTER
				do
					gtk_alloc := {GTK2}.gtk_value_pointer (p)
					Result := dimension_tuple (
						{GTK}.gtk_allocation_struct_x (gtk_alloc),
						{GTK}.gtk_allocation_struct_y (gtk_alloc),
						{GTK}.gtk_allocation_struct_width (gtk_alloc),
						{GTK}.gtk_allocation_struct_height (gtk_alloc)
					)
				end
		end

	configure_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for size allocation events
			-- see https://developer.gnome.org/gdk3/unstable/gdk3-Event-Structures.html#GdkEventConfigure
		once
			Result :=
			agent (n: INTEGER; p: POINTER): TUPLE
				local
					gdk_configure: POINTER
				do
					gdk_configure := {GTK2}.gtk_value_pointer (p)
					Result := dimension_tuple (
						{GTK}.gdk_event_configure_struct_x (gdk_configure),
						{GTK}.gdk_event_configure_struct_y (gdk_configure),
						{GTK}.gdk_event_configure_struct_width (gdk_configure),
						{GTK}.gdk_event_configure_struct_height (gdk_configure)
					)
			end
		end

	draw_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for draw events
		once
			Result := agent gtk_value_pointer_to_tuple (?, ?)
		end

	enter_leave_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for enter|leave notify events
			-- see : https://developer.gnome.org/gdk3/unstable/gdk3-Event-Structures.html#GdkEventCrossing
		once
			Result :=
			agent (n: INTEGER; p: POINTER): TUPLE
				local
					gdk_event_crossing: POINTER
				do
					gdk_event_crossing := {GTK2}.gtk_value_pointer (p)
					Result := dimension_tuple (
						{GTK}.gdk_event_crossing_struct_x (gdk_event_crossing).truncated_to_integer,
						{GTK}.gdk_event_crossing_struct_y (gdk_event_crossing).truncated_to_integer,
						{GTK}.gdk_event_crossing_struct_x_root (gdk_event_crossing).truncated_to_integer,
						{GTK}.gdk_event_crossing_struct_y_root (gdk_event_crossing).truncated_to_integer
					)
			end
		end

	response_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for dialog response events
		once
			Result := agent gtk_value_int_to_tuple (?, ?)
		end

	button_event_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
			-- Translation agent used for button events
		once
			Result := agent gtk_value_pointer_to_tuple (?, ?)
		end

	motion_notify_event_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
		once
			Result := agent gtk_value_pointer_to_tuple (?, ?)
		end

	scroll_event_translate_agent: FUNCTION [INTEGER, POINTER, TUPLE]
		once
			Result := agent gtk_value_pointer_to_tuple (?, ?)
		end

feature {EV_ANY_IMP} -- Agent implementation routines

	gtk_value_int_to_tuple (n_args: INTEGER; args: POINTER): TUPLE [INTEGER]
			-- Tuple containing integer value from first of `args'.
		do
			Result := integer_tuple
			Result.put_integer ({GTK2}.gtk_value_int (args), 1)
		end

	column_resize_callback_translate (n: INTEGER; args: POINTER): TUPLE [INTEGER, INTEGER]
			-- Translate function for MCL
		local
			gtkarg2: POINTER
		do
			gtkarg2 := {GTK2}.gtk_args_array_i_th (args, 1)
			Result := [{GTK2}.gtk_value_int (args) + 1, {GTK2}.gtk_value_int (gtkarg2)]
			-- Column is zero based in gtk.
		end

	is_destroyed: BOOLEAN
		-- Has `destroy' been called?

feature {EV_APPLICATION_IMP} -- Destruction

	destroy
			-- Destroy `Current'.
		do
			--c_ev_gtk_callback_marshal_destroy
			is_destroyed := True
		end

feature {NONE} -- Implementation

	marshal (action: ROUTINE; n_args: INTEGER; args: POINTER; a_return_value: POINTER)
			-- Call `action' with GTK+ event data from `args'.
			-- There are `n_args' GtkArg*s in `args'.
			-- Called by C function `c_ev_gtk_callback_marshal'.
		require
			action_not_void: action /= Void
			n_args_not_negative: n_args >= 0
			args_not_null: n_args > 0 implies args /= default_pointer
		local
			retry_count: INTEGER
			l_integer_pointer_tuple: detachable like integer_pointer_tuple
			l_any: detachable ANY
			b: BOOLEAN
		do
			if retry_count = 0 then
				if n_args > 0 then
					l_integer_pointer_tuple := integer_pointer_tuple
					l_integer_pointer_tuple.integer := n_args
					l_integer_pointer_tuple.pointer := args
				end
				b := False
				if attached {FUNCTION [TUPLE, detachable ANY]} action as fct then
					l_any := fct.item (l_integer_pointer_tuple)
					if attached {BOOLEAN} l_any as l_bool then
						b := l_bool
					end
				else
					action.call (l_integer_pointer_tuple)
				end

				if a_return_value /= default_pointer then
					{GTK2}.g_value_set_boolean (a_return_value, b) -- TODO: #gtk check if this is ok to return FALSE?
				end

			elseif retry_count = 1 then
				check attached {EV_APPLICATION_IMP} (create {EV_ENVIRONMENT}).implementation.application_i as app_imp then
					app_imp.on_exception_action (app_imp.new_exception)
				end
			end
		rescue
			retry_count := retry_count + 1
			if retry_count = 1 then
					-- Only retry once
				retry
			else
					-- There is an exception from calling `on_exception_action' so we exit gracefully.
				print ("Error: An exception was raised when during handling of a previous exception%N")
			end
		end

feature {NONE} -- Tuple optimizations.

	internal_dimension_tuple: TUPLE [x: INTEGER; y: INTEGER; width: INTEGER; height: INTEGER]
			-- Once function used for global access of dimension tuple.
		once
			create Result
		end

	internal_key_tuple: TUPLE [key: EV_KEY; string: STRING_32; key_press: BOOLEAN]
			-- Once function used for global access of key tuple.
		once
			create Result
		end

	pointer_tuple: TUPLE [pointer: POINTER]
		once
			create Result
		end

	integer_tuple: TUPLE [integer: INTEGER]
		once
			create Result
		end

	integer_pointer_tuple: TUPLE [integer: INTEGER; pointer: POINTER]
		once
			create Result
		end

	gtk_value_pointer_to_tuple (n_args: INTEGER; args: POINTER): TUPLE [pointer: POINTER]
			-- Tuple containing pointer value from first of `args'.
		do
			Result := pointer_tuple
			Result.pointer := {GTK2}.gtk_value_pointer (args)
		end

feature {EV_GTK_CALLBACK_MARSHAL} -- Externals

	frozen c_ev_gtk_callback_marshal_init (
		object: POINTER; a_marshal: POINTER
		)
			-- See ev_gtk_callback_marshal.c
		external
			"C inline use %"ev_gtk_callback_marshal.h%""
		alias
			"c_ev_gtk_callback_marshal_init ((EIF_REFERENCE) $object, (void (*) (EIF_REFERENCE, EIF_REFERENCE, EIF_INTEGER, EIF_POINTER, EIF_POINTER)) $a_marshal);"
		ensure
			is_class: class
		end

	frozen c_ev_gtk_callback_marshal_destroy
			-- See ev_gtk_callback_marshal.c
		external
			"C | %"ev_gtk_callback_marshal.h%""
		ensure
			is_class: class
		end

feature -- Implementation

	frozen c_ev_gtk_callback_marshal_is_enabled: BOOLEAN
			-- See ev_gtk_callback_marshal.c
		external
			"C inline use %"ev_gtk_callback_marshal.h%""
		alias
			"(EIF_BOOLEAN) c_ev_gtk_callback_marshal_is_enabled"
		ensure
			is_class: class
		end

	frozen c_ev_gtk_callback_marshal_set_is_enabled (a_enabled_state: BOOLEAN)
			-- See ev_gtk_callback_marshal.c
		external
			"C signature (int) use %"ev_gtk_callback_marshal.h%""
		ensure
			is_class: class
		end

feature {EV_ANY_IMP, EV_GTK_CALLBACK_MARSHAL} -- Externals

	frozen set_eif_oid_in_c_object (a_c_object: POINTER; eif_oid: INTEGER;
		c_object_dispose_address: POINTER)
				-- Store Eiffel object_id in `gtk_object'.
				-- Set up signal handlers.
		external
			"C macro use %"ev_any_imp.h%""
		ensure
			is_class: class
		end

	frozen c_signal_connect (a_c_object: POINTER; a_signal_name: POINTER;
		an_agent: ROUTINE; invoke_after_handler: BOOLEAN): INTEGER
			-- Connect `an_agent' to 'a_signal_name' on `a_c_object'.
		external
			"C (gpointer, gchar*, EIF_OBJECT, gboolean): guint | %"ev_gtk_callback_marshal.h%""
		alias
			"c_ev_gtk_callback_marshal_signal_connect"
		ensure
			is_class: class
		end

feature {EV_APPLICATION_IMP, EV_TIMEOUT_IMP} -- Externals

	frozen c_ev_gtk_callback_marshal_timeout_connect
		(a_delay: INTEGER; an_agent: PROCEDURE): NATURAL_32
			-- Call `an_agent' after `a_delay'.
		external
			"C (gint, EIF_OBJECT): EIF_INTEGER | %"ev_gtk_callback_marshal.h%""
		ensure
			is_class: class
		end

note
	copyright:	"Copyright (c) 1984-2021, Eiffel Software and others"
	license:	"Eiffel Forum License v2 (see http://www.eiffel.com/licensing/forum.txt)"
	source: "[
			Eiffel Software
			5949 Hollister Ave., Goleta, CA 93117 USA
			Telephone 805-685-1006, Fax 805-685-6869
			Website http://www.eiffel.com
			Customer support http://support.eiffel.com
		]"

end -- class EV_GTK_CALLBACK_MARSHAL











