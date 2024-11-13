---@class OrgEvent
---@field type string

return {
  AttachChanged = require('orgmode.events.types.attach_changed_event'),
  AttachOpened = require('orgmode.events.types.attach_opened_event'),
  HeadlineArchived = require('orgmode.events.types.headline_archived_event'),
  HeadlineDemoted = require('orgmode.events.types.headline_demoted_event'),
  HeadlinePromoted = require('orgmode.events.types.headline_promoted_event'),
  TodoChanged = require('orgmode.events.types.todo_changed_event'),
}
