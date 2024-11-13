---@class OrgDefaultConfig
---@field org_id_method 'uuid' | 'ts' | 'org'
---@field org_agenda_span 'day' | 'week' | 'month' | 'year' | number
---@field org_log_repeat 'time' | 'note' | false
---@field calendar { round_min_with_hours: boolean, min_big_step: number, min_small_step: number? }
---@field org_attach_preferred_new_method 'id' | 'dir' | 'ask' | false
---@field org_attach_method 'mv' | 'cp' | 'ln' | 'lns'
---@field org_attach_use_inheritance true | false | 'selective'
---@field org_attach_store_link_p true | false | 'file' | 'attached'
---@field org_attach_archive_delete true | false | 'query'
---@field org_attach_id_to_path_function_list (function|string)[]
---@field org_attach_after_change_hook function?
---@field org_attach_open_hook function?
---@field org_attach_sync_delete_empty_dir true | false | 'query'
local DefaultConfig = {
  org_agenda_files = '',
  org_default_notes_file = '',
  org_todo_keywords = { 'TODO', '|', 'DONE' },
  org_todo_repeat_to_state = nil,
  org_todo_keyword_faces = {},
  org_deadline_warning_days = 14,
  org_agenda_min_height = 16,
  org_agenda_span = 'week',   -- day/week/month/year/number of days
  org_agenda_start_on_weekday = 1,
  org_agenda_start_day = nil, -- start from today + this modifier
  calendar_week_start_day = 1,
  calendar = {
    round_min_with_hours = true,
    min_big_step = 15,
  },
  org_capture_templates = {
    t = {
      description = 'Task',
      template = '* TODO %?\n  %u',
    },
  },
  org_startup_folded = 'overview',
  org_agenda_skip_scheduled_if_done = false,
  org_agenda_skip_deadline_if_done = false,
  org_agenda_text_search_extra_files = {},
  org_priority_highest = 'A',
  org_priority_default = 'B',
  org_priority_lowest = 'C',
  org_priority_start_cycle_with_default = true,
  org_archive_location = '%s_archive::',
  org_tags_column = -80,
  org_use_tag_inheritance = true,
  org_tags_exclude_from_inheritance = {},
  org_hide_leading_stars = false,
  org_hide_emphasis_markers = false,
  org_ellipsis = '...',
  org_log_done = 'time',
  org_log_repeat = 'time',
  org_log_into_drawer = nil,
  org_highlight_latex_and_related = nil,
  org_custom_exports = {},
  org_adapt_indentation = true,
  org_startup_indented = false,
  org_indent_mode_turns_off_org_adapt_indentation = true,
  org_indent_mode_turns_on_hiding_stars = true,
  org_time_stamp_rounding_minutes = 5,
  org_blank_before_new_entry = {
    heading = true,
    plain_list_item = false,
  },
  org_src_window_setup = 'top 16new',
  org_edit_src_content_indentation = 0,
  org_id_uuid_program = 'uuidgen',
  org_id_ts_format = '%Y%m%d%H%M%S',
  org_id_method = 'uuid',
  org_id_prefix = nil,
  org_id_link_to_org_use_id = false,
  org_babel_default_header_args = {
    [':tangle'] = 'no',
    [':noweb'] = 'no',
  },
  org_attach_id_dir = './data/', --[[The directory where attachments are stored. If this is a relative path, it will be interpreted relative to the directory where the Org file lives.]]
  org_attach_dir_relative = false, --[[True means directories in DIR property are added as relative links. Defaults to absolute location.]]
  org_attach_auto_tag = 'ATTACH', --[[Tag that will be triggered automatically when an entry has an attachment.]]
  org_attach_preferred_new_method = 'id', --[[Preferred way to attach to nodes without existing ID and DIR property.
  This choice is used when adding attachments to nodes without ID
  and DIR properties.

  Allowed values are:

  id         Create and use an ID parameter
  dir        Create and use a DIR parameter
  ask        Ask the user for input of which method to choose
  false      Prefer to not create a new parameter

             false means that ID or DIR has to be created explicitly
             before attaching files.]]
  org_attach_method = 'cp', --[[The preferred method to attach a file.
  Allowed values are:

  mv    rename the file to move it into the attachment directory
  cp    copy the file
  ln    create a hard link.  Note that this is not supported
        on all systems, and then the result is not defined.
  lns   create a symbol link.  Note that this is not supported
        on all systems, and then the result is not defined.]]
  org_attach_expert = false, --[[True means do not show the splash buffer with the attach dispatcher.]]
  org_attach_use_inheritance = 'selective', --[[Attachment inheritance for the outline.

  Enabling inheritance for `org-attach' implies two things.  First,
  that attachment links will look through all parent headings until
  it finds the linked attachment.  Second, that running `org-attach'
  inside a node without attachments will make `org-attach' operate on
  the first parent heading it finds with an attachment.

  Selective means to respect the inheritance setting in
  `org-use-property-inheritance'."
  True means to inherit attachments. False means not to inherit them.
  ]]
  org_attach_store_link_p = 'attached', --[[A truthy value means store a link to a file when attaching it.

  When true, store the link to original file location.
  When 'file', store file link to the attach-dir location.
  When 'attached', store attachment link to the attach-dir location.]]
  org_attach_archive_delete = false, --[[True means attachments are deleted upon archiving a subtree.
  When set to 'query', ask the user instead.]]
  org_attach_id_to_path_function_list = {
    'uuid-folder-format', 'ts-folder-format', 'fallback-folder-format',
  }, --[[List of functions used to derive attachment path from an ID string.
  The functions are called with a single ID argument until the return
  value is an existing folder.  If no folder has been created yet for
  the given ID, then the first truthy value defines the attachment
  dir to be created.

  Usually, the ID format passed to the functions is defined by
  `org_id_method`.  It is advised that the first function in the list do
  not generate all the attachment dirs inside the same parent dir.  Some
  file systems may have performance issues in such scenario.

  Care should be taken when customizing this variable.  Previously
  created attachment folders might not be correctly mapped upon removing
  functions from the list.  Then, Org will not be able to detect the
  existing attachments.]]
  org_attach_after_change_hook = nil, --[[Hook called when files have been added or removed to the attachment folder.]]
  org_attach_open_hook = nil, --[[Hook that is invoked by `org-attach-open'.

  Created mostly to be compatible with org-attach-git after removing
  git-functionality from this file.]]
  org_attach_sync_delete_empty_dir = 'query', --[[Determine what to do with an empty attachment directory on sync.
  When set to false, don't touch the directory.  When set to 'query',
  ask the user instead, else remove without asking.]]
  win_split_mode = 'horizontal',
  win_border = 'single',
  notifications = {
    enabled = false,
    cron_enabled = true,
    repeater_reminder_time = false,
    deadline_warning_reminder_time = 0,
    reminder_time = 10,
    deadline_reminder = true,
    scheduled_reminder = true,
  },
  mappings = {
    disable_all = false,
    org_return_uses_meta_return = false,
    prefix = '<Leader>o',
    global = {
      org_agenda = '<prefix>a',
      org_capture = '<prefix>c',
    },
    agenda = {
      org_agenda_later = 'f',
      org_agenda_earlier = 'b',
      org_agenda_goto_today = '.',
      org_agenda_day_view = 'vd',
      org_agenda_week_view = 'vw',
      org_agenda_month_view = 'vm',
      org_agenda_year_view = 'vy',
      org_agenda_quit = 'q',
      org_agenda_switch_to = '<CR>',
      org_agenda_goto = '<TAB>',
      org_agenda_goto_date = 'J',
      org_agenda_redo = 'r',
      org_agenda_todo = 't',
      org_agenda_clock_goto = '<prefix>xj',
      org_agenda_set_effort = '<prefix>xe',
      org_agenda_clock_in = 'I',
      org_agenda_clock_out = 'O',
      org_agenda_clock_cancel = 'X',
      org_agenda_clockreport_mode = 'R',
      org_agenda_priority = '<prefix>,',
      org_agenda_priority_up = '+',
      org_agenda_priority_down = '-',
      org_agenda_archive = '<prefix>$',
      org_agenda_toggle_archive_tag = '<prefix>A',
      org_agenda_set_tags = '<prefix>t',
      org_agenda_deadline = '<prefix>id',
      org_agenda_schedule = '<prefix>is',
      org_agenda_filter = '/',
      org_agenda_refile = '<prefix>r',
      org_agenda_add_note = '<prefix>na',
      org_agenda_show_help = 'g?',
    },
    capture = {
      org_capture_finalize = '<C-c>',
      org_capture_refile = '<prefix>r',
      org_capture_kill = '<prefix>k',
      org_capture_show_help = 'g?',
    },
    note = {
      org_note_finalize = '<C-c>',
      org_note_kill = '<prefix>k',
    },
    org = {
      org_refile = '<prefix>r',
      org_timestamp_up_day = '<S-UP>',
      org_timestamp_down_day = '<S-DOWN>',
      org_timestamp_up = '<C-a>',
      org_timestamp_down = '<C-x>',
      org_change_date = 'cid',
      org_priority = '<prefix>,',
      org_priority_up = 'ciR',
      org_priority_down = 'cir',
      org_todo = 'cit',
      org_todo_prev = 'ciT',
      org_toggle_checkbox = '<C-Space>',
      org_toggle_heading = '<prefix>*',
      org_open_at_point = '<prefix>o',
      org_edit_special = [[<prefix>']],
      org_add_note = '<prefix>na',
      org_cycle = '<TAB>',
      org_global_cycle = '<S-TAB>',
      org_archive_subtree = '<prefix>$',
      org_set_tags_command = '<prefix>t',
      org_toggle_archive_tag = '<prefix>A',
      org_do_promote = '<<',
      org_do_demote = '>>',
      org_promote_subtree = '<s',
      org_demote_subtree = '>s',
      org_meta_return = '<Leader><CR>',                       -- Add heading, item or row (context-dependent)
      org_return = '<CR>',
      org_insert_heading_respect_content = '<prefix>ih',      -- Add new heading after current heading block (same level)
      org_insert_todo_heading = '<prefix>iT',                 -- Add new todo heading right after current heading (same level)
      org_insert_todo_heading_respect_content = '<prefix>it', -- Add new todo heading after current heading block (same level)
      org_move_subtree_up = '<prefix>K',
      org_move_subtree_down = '<prefix>J',
      org_export = '<prefix>e',
      org_next_visible_heading = '}',
      org_previous_visible_heading = '{',
      org_forward_heading_same_level = ']]',
      org_backward_heading_same_level = '[[',
      outline_up_heading = 'g{',
      org_deadline = '<prefix>id',
      org_schedule = '<prefix>is',
      org_time_stamp = '<prefix>i.',
      org_time_stamp_inactive = '<prefix>i!',
      org_toggle_timestamp_type = '<prefix>d!',
      org_insert_link = '<prefix>li',
      org_store_link = '<prefix>ls',
      org_clock_in = '<prefix>xi',
      org_clock_out = '<prefix>xo',
      org_clock_cancel = '<prefix>xq',
      org_clock_goto = '<prefix>xj',
      org_set_effort = '<prefix>xe',
      org_show_help = 'g?',
      org_babel_tangle = '<prefix>bt',
      org_attach = '<prefix><C-A>',
    },
    edit_src = {
      org_edit_src_abort = '<prefix>k',
      org_edit_src_save = '<prefix>w',
      org_edit_src_show_help = 'g?',
    },
    text_objects = {
      inner_heading = 'ih',
      around_heading = 'ah',
      inner_subtree = 'ir',
      around_subtree = 'ar',
      inner_heading_from_root = 'Oh',
      around_heading_from_root = 'OH',
      inner_subtree_from_root = 'Or',
      around_subtree_from_root = 'OR',
    },
  },
  emacs_config = {
    executable_path = 'emacs',
    config_path = '$HOME/.emacs.d/init.el',
  },
  ui = {
    folds = {
      colored = true,
    },
    menu = {
      handler = nil,
    },
  },
}

return DefaultConfig
