-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local clusters = require "st.matter.clusters"

local IkeaScrollFields = {}

-- PowerSource supported on Root Node
IkeaScrollFields.ENDPOINT_POWER_SOURCE = 0

-- Generic Switch Endpoints used for basic push functionality
IkeaScrollFields.ENDPOINTS_PUSH = {3, 6, 9}

-- Generic Switch Endpoints used for Up Scroll functionality
IkeaScrollFields.ENDPOINTS_UP_SCROLL = {1, 4, 7}

-- Generic Switch Endpoints used for Down Scroll functionality
IkeaScrollFields.ENDPOINTS_DOWN_SCROLL = {2, 5, 8}

-- Maximum number of presses at a time
IkeaScrollFields.MAX_SCROLL_PRESSES = 18

-- Amount to rotate per scroll event
IkeaScrollFields.PER_SCROLL_EVENT_ROTATION = st_utils.round(1 / IkeaScrollFields.MAX_SCROLL_PRESSES * 100)

-- Field to track the latest number of presses counted during a single scroll event sequence
IkeaScrollFields.LATEST_NUMBER_OF_PRESSES_COUNTED = "__latest_number_of_presses_counted"

-- Time-window accumulation fields for scroll events

-- Whether the debounce window is currently active (true while user is scrolling)
IkeaScrollFields.SCROLL_DEBOUNCE_ACTIVE_KEY = "__scroll_debounce_active"

-- Accumulated scroll values per endpoint: {[ep_id] = accum_val}
IkeaScrollFields.SCROLL_ACCUM_KEY = "__scroll_accum_vals"

-- Handle for the debounce timer; when it expires (no scroll for DEBOUNCE_TIMEOUT),
-- accumulated values are flushed and the window closes
IkeaScrollFields.SCROLL_DEBOUNCE_TIMER_KEY = "__scroll_debounce_timer"

-- Seconds of inactivity before flushing accumulated values and closing the window
IkeaScrollFields.SCROLL_DEBOUNCE_TIMEOUT = 1

-- Handle for the periodic emit timer; emits accumulated values every
-- PERIODIC_EMIT_INTERVAL while the debounce window is still active
IkeaScrollFields.SCROLL_PERIODIC_EMIT_TIMER_KEY = "__scroll_periodic_emit_timer"

-- Seconds between periodic intermediate emits during an active scroll session
IkeaScrollFields.SCROLL_PERIODIC_EMIT_INTERVAL = 2

-- Handle for the initial emit timer; fires once after INITIAL_EMIT_DELAY to emit
-- the first batch of accumulated values, providing quicker feedback than waiting
-- for the periodic emit
IkeaScrollFields.SCROLL_INITIAL_EMIT_TIMER_KEY = "__scroll_initial_emit_timer"

-- Seconds to accumulate before the first emit after scrolling starts
IkeaScrollFields.SCROLL_INITIAL_EMIT_DELAY = 0.8

-- Required Events for the ENDPOINTS_PUSH.
IkeaScrollFields.switch_press_subscribed_events = {
  clusters.Switch.events.InitialPress.ID,
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
}

-- Required Events for the ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL. Adds a
-- MultiPressOngoing subscription to handle step functionality in real-time
IkeaScrollFields.switch_scroll_subscribed_events = {
  clusters.Switch.events.InitialPress.ID,
  clusters.Switch.events.MultiPressOngoing.ID,
  clusters.Switch.events.MultiPressComplete.ID,
}

return IkeaScrollFields
