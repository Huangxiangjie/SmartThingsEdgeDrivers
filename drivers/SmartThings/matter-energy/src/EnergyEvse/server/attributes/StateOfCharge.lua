local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local StateOfCharge = {
  ID = 0x0030,
  NAME = "StateOfCharge",
  base_type = data_types.Uint8,
}

function StateOfCharge:new_value(...)
  local o = self.base_type(table.unpack({...}))
  return o
end

function StateOfCharge:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function StateOfCharge:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function StateOfCharge:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function StateOfCharge:build_test_report_data(
  device,
  endpoint_id,
  value,
  status
)
  local data = data_types.validate_or_build_type(value, self.base_type)
  return cluster_base.build_test_report_data(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    data,
    status
  )
end

function StateOfCharge:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  return data
end

setmetatable(StateOfCharge, {__call = StateOfCharge.new_value})
return StateOfCharge
