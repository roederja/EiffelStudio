note
	description: "[
			Objects that ...
		]"
	author: "$Author$"
	date: "$Date$"
	revision: "$Revision$"

class
	GIT_ENGINE

inherit
	SHARED_PROCESS_MISC
		redefine
			default_create
		end

create
	default_create,
	make_with_executable_path

feature {NONE} -- Initialization

	default_create
		do
			make_with_executable_path ("git")
		end

	make_with_executable_path (v: READABLE_STRING_GENERAL)
		do
			set_git_executable_path (v)
		end

feature -- Access

	git_executable_location: PATH

feature -- Element change

	set_git_executable_path (v: READABLE_STRING_GENERAL)
		do
			set_git_executable_location (create {PATH}.make_from_string (v))
		end

	set_git_executable_location (v: PATH)
		do
			git_executable_location := v
		end

feature -- Access tool info

	version: detachable IMMUTABLE_STRING_32
		local
			res: detachable PROCESS_COMMAND_RESULT
			cmd: STRING_32
		do
			create cmd.make_from_string (git_executable_location.name)
			cmd.append_string (" --version")
			res := output_of_command (cmd, Void)
			if res /= Void and then res.exit_code = 0 then
				create Result.make_from_string_general (res.output)
			end
		end

feature -- Execution

	statuses (a_root_location, a_path: PATH; is_recursive: BOOLEAN; a_options: detachable SCM_OPTIONS): detachable SCM_STATUS_LIST
		local
			res: detachable PROCESS_COMMAND_RESULT
			s: detachable READABLE_STRING_8
			cmd: STRING_32
		do
			create cmd.make_from_string (git_executable_location.name)
			cmd.append_string_general (" status")
			cmd.append_string (option_to_command_line_flags ("status", a_options))


			cmd.append_string_general (" --porcelain=v1 --no-renames")
			cmd.append_string_general (" .")

			debug ("GIT_ENGINE")
				print ({STRING_32} "Command: [" + cmd + "]%N")
			end
			res := output_of_command (cmd, a_path)
			debug ("GIT_ENGINE")
				print ("-> terminated %N")
			end
			if res = Void then
				debug ("GIT_ENGINE")
					print ("-> terminated : None .%N")
				end
			else
				s := res.output
				Result := status_from_porcelain_output (a_root_location, {UTF_CONVERTER}.utf_8_string_8_to_string_32 (s))
				debug ("GIT_ENGINE")
					print ("-> terminated : count=" + s.count.out + " .%N")
					print (s)
				end
			end
		end

	diff (a_path: PATH; a_options: detachable SCM_OPTIONS): detachable SCM_RESULT
		local
			res: detachable PROCESS_COMMAND_RESULT
			s: detachable READABLE_STRING_8
			cmd: STRING_32
			fut: FILE_UTILITIES
		do
			create cmd.make_from_string (git_executable_location.name)
			cmd.append_string_general (" diff")
			cmd.append_string (option_to_command_line_flags ("diff", a_options))

			debug ("GIT_ENGINE")
				print ({STRING_32} "Command: [" + cmd + "]%N")
			end
			if fut.file_path_exists (a_path) then
				cmd.append_string_general (" %"")
				cmd.append_string_general (a_path.name)
				cmd.append_string_general ("%"")
				res := output_of_command (cmd, a_path.parent)
			else
				cmd.append_string_general (" . ")
				res := output_of_command (cmd, a_path)
			end
			debug ("GIT_ENGINE")
				print ("-> terminated %N")
			end
			if res = Void then
				debug ("GIT_ENGINE")
					print ("-> terminated : None .%N")
				end
			else
				s := res.output
				create Result.make_with_command (cmd)
				Result.set_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (s))
				debug ("GIT_ENGINE")
					print ("-> terminated : count=" + s.count.out + " .%N")
					print (s)
				end
			end
		end

	revert (a_changelist: SCM_CHANGELIST; a_options: detachable SCM_OPTIONS): SCM_RESULT
		local
			cmd: STRING_32
			fn: READABLE_STRING_32
		do
			create cmd.make_from_string (git_executable_location.name)
			cmd.append_string (option_to_command_line_flags ("checkout", a_options))
			cmd.append_string_general (" checkout -- ")
			across
				a_changelist as ic
			loop
				fn := ic.item.location.name
				cmd.append_character (' ')
				if fn.has (' ') or fn.has ('%T') then
					cmd.append_character ('"')
					cmd.append_string_general (fn)
					cmd.append_character ('"')
				else
					cmd.append_string_general (fn)
				end
			end

			debug ("GIT_ENGINE")
				print ({STRING_32} "Command: [" + cmd + "]%N")
			end
			if attached output_of_command (cmd, a_changelist.root.location) as res_revert then
				if res_revert.exit_code = 0 then
					create Result.make_success (cmd)
					Result.set_message (res_revert.output)
				else
					create Result.make_failure (cmd)
					Result.set_message (res_revert.error_output)
				end
			else
				create Result.make_failure (cmd)
				Result.set_message ("Error: can not launch git [" + process_misc.last_error.out + "]")
			end
			debug ("GIT_ENGINE")
				print ("-> terminated %N")
			end
		end

	commit (a_changelist: SCM_CHANGELIST; a_log_message: READABLE_STRING_GENERAL; a_options: SCM_OPTIONS): SCM_RESULT
			-- Commit changes for locations `a_changelist`, and return information about command execution.
		local
			cmd: STRING_32
			fn: READABLE_STRING_32
		do
			create cmd.make_from_string (git_executable_location.name)
			cmd.append_string_general (" add")
			cmd.append_string (option_to_command_line_flags ("add", a_options))
			across
				a_changelist as ic
			loop
				fn := ic.item.location.name
				cmd.append_character (' ')
				if fn.has (' ') or fn.has ('%T') then
					cmd.append_character ('"')
					cmd.append_string_general (fn)
					cmd.append_character ('"')
				else
					cmd.append_string_general (fn)
				end
			end

			debug ("GIT_ENGINE")
				print ({STRING_32} "Command: [" + cmd + "]%N")
			end
			if attached output_of_command (cmd, a_changelist.root.location) as res_add then
					-- Todo
			end
			debug ("GIT_ENGINE")
				print ("-> terminated %N")
			end

			create cmd.make_from_string (git_executable_location.name)
			cmd.append_string_general (" commit")
			cmd.append_string (option_to_command_line_flags ("commit", a_options))
			cmd.append_string_general (" --message ")
			cmd.append_character ('"')
			append_escaped_string_to (a_log_message, cmd)
			cmd.append_character ('"')

			debug ("GIT_ENGINE")
				print ({STRING_32} "Command: [" + cmd + "]%N")
			end
			if attached output_of_command (cmd, a_changelist.root.location) as res_commit then
				if res_commit.exit_code = 0 then
					create Result.make_success (cmd)
					Result.set_message (res_commit.output)
				else
					create Result.make_failure (cmd)
					Result.set_message (res_commit.error_output)
				end
			else
				create Result.make_failure (cmd)
				Result.set_message ("Error: can not launch git [" + process_misc.last_error.out + "]")
			end
			debug ("GIT_ENGINE")
				print ("-> terminated %N")
			end
		end

feature {NONE} -- Implementation

	append_escaped_string_to (a_string: READABLE_STRING_GENERAL; a_output: STRING_32)
		local
			i,n: INTEGER
			ch: CHARACTER_32
		do
			if a_string.has ('%"') then
				from
					i := 1
					n := a_string.count
				until
					i > n
				loop
					ch := a_string [i]
					inspect ch
					when '%"' then
						a_output.extend ('\')
						a_output.extend (ch)
					when '%R' then
						-- Ignore
					when '%N' then
						a_output.extend ('\')
						a_output.extend ('n')
					when '\' then
						a_output.extend (ch)
						if i < n then
							ch := a_string [i]
							a_output.extend (ch)
							i := i + 1
						end
					else
						a_output.extend (ch)
					end
					i := i + 1
				end
			else
				a_output.append_string_general (a_string)
			end
		end

	status_from_porcelain_output (a_path: PATH; s: READABLE_STRING_32): SCM_STATUS_LIST
		local
			i,j,n: INTEGER
			l_line: STRING_32
			k: READABLE_STRING_GENERAL
		do
			create Result.make (0)
			from
				n := s.count
				i := 1
			until
				i > n
			loop
				j := s.index_of ('%N', i)
				if j > 0 then
					l_line := s.substring (i, j - 1)
					i := j + 1
				else
					l_line := s.substring (i, n)
					i := n + 1
				end
				l_line.left_adjust
				j := l_line.index_of (' ', 1)
				k := l_line.head (j - 1)
				l_line.remove_head (j)
				l_line.left_adjust
				if k.has ('M') then
					Result.force (create {SCM_STATUS_MODIFIED}.make (a_path.extended (l_line)))
				elseif k.has ('A') then
					Result.force (create {SCM_STATUS_ADDED}.make (a_path.extended (l_line)))
				elseif k.has ('D') then
					Result.force (create {SCM_STATUS_DELETED}.make (a_path.extended (l_line)))
				elseif k.has ('C') then
					Result.force (create {SCM_STATUS_CONFLICTED}.make (a_path.extended (l_line)))
				elseif k.has ('?') then
					Result.force (create {SCM_STATUS_UNVERSIONED}.make (a_path.extended (l_line)))
				end
			end
		end

	option_to_command_line_flags (a_command: READABLE_STRING_GENERAL; a_options: detachable SCM_OPTIONS): STRING_32
		local
			p: READABLE_STRING_GENERAL
		do
			create Result.make_empty
			if a_options /= Void then
				if a_options.is_simulation and a_command.is_case_insensitive_equal ("commit") then
					Result.append_string_general (" --dry-run ")
				end
				if attached a_options.parameters as l_params then
					across
						l_params as ic
					loop
						p := ic.item
						if not p.is_whitespace then
							Result.append_string_general (" ")
							Result.append (p)
							Result.append_string_general (" ")
						end
					end
				end
			end
		end

invariant
--	invariant_clause: True

note
	copyright: "Copyright (c) 1984-2021, Eiffel Software and others"
	license: "Eiffel Forum License v2 (see http://www.eiffel.com/licensing/forum.txt)"
	source: "[
			Eiffel Software
			5949 Hollister Ave., Goleta, CA 93117 USA
			Telephone 805-685-1006, Fax 805-685-6869
			Website http://www.eiffel.com
			Customer support http://support.eiffel.com
		]"
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
end
