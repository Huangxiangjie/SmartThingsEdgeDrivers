-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local generic_event_handlers = require "switch_handlers.event_handlers"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollEventHandlers = {}

-- Emit accumulated scroll values for all endpoints that have non-zero values
local function emit_accumulated(device)
  local accum_table = device:get_field(scroll_fields.SCROLL_ACCUM_KEY) or {}

  local log_parts = {}
  for ep_id, accum_val in pairs(accum_table) do
    if accum_val ~= 0 then
      device:emit_event_for_endpoint(ep_id, capabilities.knob.rotateAmount(accum_val, {state_change = true}))
      table.insert(log_parts, string.format("ep%d=%d", ep_id, accum_val))
    end
  end

  if #log_parts > 0 then
    device.log.info_with({ hub_logs = true },
      string.format("[IkeaScroll] Scroll emit: %s", table.concat(log_parts, ", ")))
  end

  return #log_parts > 0  -- return whether any values were emitted
end

-- Flush accumulated values and close the window (user stopped scrolling)
local function flush_and_close(device)
  -- Cancel the initial emit timer
  local initial_timer = device:get_field(scroll_fields.SCROLL_INITIAL_EMIT_TIMER_KEY)
  if initial_timer then
    pcall(function() device.thread:cancel_timer(initial_timer) end)
  end

  -- Cancel the periodic emit timer
  local report_timer = device:get_field(scroll_fields.SCROLL_PERIODIC_EMIT_TIMER_KEY)
  if report_timer then
    pcall(function() device.thread:cancel_timer(report_timer) end)
  end

  emit_accumulated(device)
  device:set_field(scroll_fields.SCROLL_DEBOUNCE_ACTIVE_KEY, false)
  device:set_field(scroll_fields.SCROLL_DEBOUNCE_TIMER_KEY, nil)
  device:set_field(scroll_fields.SCROLL_PERIODIC_EMIT_TIMER_KEY, nil)
  device:set_field(scroll_fields.SCROLL_INITIAL_EMIT_TIMER_KEY, nil)
  device:set_field(scroll_fields.SCROLL_ACCUM_KEY, {})
end

-- Periodic emit: emit accumulated values every PERIODIC_EMIT_INTERVAL while scrolling
local function periodic_report(device)
  local debounce_active = device:get_field(scroll_fields.SCROLL_DEBOUNCE_ACTIVE_KEY)
  if not debounce_active then
    -- Window already closed, stop reporting
    device:set_field(scroll_fields.SCROLL_PERIODIC_EMIT_TIMER_KEY, nil)
    return
  end

  local emitted = emit_accumulated(device)
  if emitted then
    -- Clear accumulation after emitting
    device:set_field(scroll_fields.SCROLL_ACCUM_KEY, {})
  end

  -- Restart the periodic report timer
  local timer = device.thread:call_with_delay(scroll_fields.SCROLL_PERIODIC_EMIT_INTERVAL, function()
    periodic_report(device)
  end)
  device:set_field(scroll_fields.SCROLL_PERIODIC_EMIT_TIMER_KEY, timer)
end

-- Initial emit: emit accumulated values once after INITIAL_EMIT_DELAY, then start
-- the debounce timer. The debounce timer only begins counting after the first emit,
-- so the 1s idle timeout is measured from the last event after initial emit.
local function initial_emit(device)
  local debounce_active = device:get_field(scroll_fields.SCROLL_DEBOUNCE_ACTIVE_KEY)
  if not debounce_active then
    device:set_field(scroll_fields.SCROLL_INITIAL_EMIT_TIMER_KEY, nil)
    return
  end

  local emitted = emit_accumulated(device)
  if emitted then
    device:set_field(scroll_fields.SCROLL_ACCUM_KEY, {})
  end
  device:set_field(scroll_fields.SCROLL_INITIAL_EMIT_TIMER_KEY, nil)

  -- Start the debounce timer now that initial emit has fired
  local timer = device.thread:call_with_delay(scroll_fields.SCROLL_DEBOUNCE_TIMEOUT, function()
    flush_and_close(device)
  end)
  device:set_field(scroll_fields.SCROLL_DEBOUNCE_TIMER_KEY, timer)

  -- Start the periodic emit timer now that initial emit has fired
  local report_timer = device.thread:call_with_delay(scroll_fields.SCROLL_PERIODIC_EMIT_INTERVAL, function()
    periodic_report(device)
  end)
  device:set_field(scroll_fields.SCROLL_PERIODIC_EMIT_TIMER_KEY, report_timer)

  device.log.info_with({ hub_logs = true },
    string.format("[IkeaScroll] Initial emit fired after %.1fs, debounce and periodic timers started", scroll_fields.SCROLL_INITIAL_EMIT_DELAY))
end

-- Start a new debounce window (debounce and periodic timers start after initial emit)
local function start_debounce_window(device)
  device:set_field(scroll_fields.SCROLL_DEBOUNCE_ACTIVE_KEY, true)
  device:set_field(scroll_fields.SCROLL_ACCUM_KEY, {})
  device:set_field(scroll_fields.SCROLL_DEBOUNCE_TIMER_KEY, nil)
  device:set_field(scroll_fields.SCROLL_PERIODIC_EMIT_TIMER_KEY, nil)

  -- Initial emit timer: emit first batch of accumulated values after INITIAL_EMIT_DELAY
  local initial_timer = device.thread:call_with_delay(scroll_fields.SCROLL_INITIAL_EMIT_DELAY, function()
    initial_emit(device)
  end)
  device:set_field(scroll_fields.SCROLL_INITIAL_EMIT_TIMER_KEY, initial_timer)
end

-- Reset (restart) the debounce timer without clearing accumulated values
local function reset_debounce_timer(device)
  local existing_timer = device:get_field(scroll_fields.SCROLL_DEBOUNCE_TIMER_KEY)
  if existing_timer then
    pcall(function() device.thread:cancel_timer(existing_timer) end)
  end

  local timer = device.thread:call_with_delay(scroll_fields.SCROLL_DEBOUNCE_TIMEOUT, function()
    flush_and_close(device)
  end)
  device:set_field(scroll_fields.SCROLL_DEBOUNCE_TIMER_KEY, timer)
end

local function rotate_amount_event_helper(device, endpoint_id, num_presses_to_handle)
  -- to cut down on checks, we can assume that if the endpoint is not in ENDPOINTS_UP_SCROLL, it is in ENDPOINTS_DOWN_SCROLL
  local scroll_direction = switch_utils.tbl_contains(scroll_fields.ENDPOINTS_UP_SCROLL, endpoint_id) and 1 or -1
  local scroll_amount = st_utils.clamp_value(scroll_direction * scroll_fields.PER_SCROLL_EVENT_ROTATION * num_presses_to_handle, -100, 100)

  local debounce_active = device:get_field(scroll_fields.SCROLL_DEBOUNCE_ACTIVE_KEY)

  if not debounce_active then
    -- First trigger: start debounce window and accumulate (initial emit fires after INITIAL_EMIT_DELAY)
    start_debounce_window(device)

    local accum_table = device:get_field(scroll_fields.SCROLL_ACCUM_KEY) or {}
    accum_table[endpoint_id] = st_utils.clamp_value(scroll_amount, -100, 100)
    device:set_field(scroll_fields.SCROLL_ACCUM_KEY, accum_table)

    device.log.info_with({ hub_logs = true },
      string.format("[IkeaScroll] Scroll first trigger: ep=%d, amount=%d, starting %.1fs debounce window (initial emit in %.1fs)", endpoint_id, scroll_amount, scroll_fields.SCROLL_DEBOUNCE_TIMEOUT, scroll_fields.SCROLL_INITIAL_EMIT_DELAY))
  else
    -- Within the window: accumulate value per endpoint
    local accum_table = device:get_field(scroll_fields.SCROLL_ACCUM_KEY) or {}
    local current = accum_table[endpoint_id] or 0
    accum_table[endpoint_id] = st_utils.clamp_value(current + scroll_amount, -100, 100)
    device:set_field(scroll_fields.SCROLL_ACCUM_KEY, accum_table)

    -- Debounce: reset timer on each new event so we emit shortly after user pauses
    -- (only if debounce timer has been started, i.e. initial emit already fired)
    if device:get_field(scroll_fields.SCROLL_DEBOUNCE_TIMER_KEY) then
      reset_debounce_timer(device)
    end

    device.log.info_with({ hub_logs = true },
      string.format("[IkeaScroll] Scroll accumulating: ep=%d, amount=%d, accum=%d", endpoint_id, scroll_amount, accum_table[endpoint_id]))
  end
end

-- Used by ENDPOINTS_UP_SCROLL and ENDPOINTS_DOWN_SCROLL, not ENDPOINTS_PUSH
function IkeaScrollEventHandlers.multi_press_ongoing_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    -- Ignore MultiPressOngoing events from push endpoints.
    device.log.debug("Received MultiPressOngoing event from push endpoint, ignoring.")
  else
    local cur_num_presses_counted = ib.data and ib.data.elements and ib.data.elements.current_number_of_presses_counted.value or 0
    local num_presses_to_handle = cur_num_presses_counted - (device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED) or 0)
    if num_presses_to_handle > 0 then
      device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED, cur_num_presses_counted)
      rotate_amount_event_helper(device, ib.endpoint_id, num_presses_to_handle)
    end
  end
end

function IkeaScrollEventHandlers.multi_press_complete_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.multi_press_complete_handler(driver, device, ib, response)
  else
    local total_num_presses_counted = ib.data and ib.data.elements and ib.data.elements.total_number_of_presses_counted.value or 0
    local num_presses_to_handle = total_num_presses_counted - (device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED) or 0)
    if num_presses_to_handle > 0 then
      rotate_amount_event_helper(device, ib.endpoint_id, num_presses_to_handle)
    end
    -- reset the LATEST_NUMBER_OF_PRESSES_COUNTED to nil at the end of a MultiPress chain.
    device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED, nil)
  end
end

function IkeaScrollEventHandlers.initial_press_handler(driver, device, ib, response)
  if switch_utils.tbl_contains(scroll_fields.ENDPOINTS_PUSH, ib.endpoint_id) then
    generic_event_handlers.initial_press_handler(driver, device, ib, response)
  else
    -- the magic number "1" occurs in this handler since the InitialPress event represents the first press.
    local latest_presses_counted = device:get_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED) or 0
    if latest_presses_counted == 0 then
      device:set_field(scroll_fields.LATEST_NUMBER_OF_PRESSES_COUNTED, 1)
      rotate_amount_event_helper(device, ib.endpoint_id, 1)
    end
  end
end

return IkeaScrollEventHandlers
