local pb = require("pb")
local json = require("cjson")

-- Load the descriptor set
local f = assert(io.open("/usr/lib/x86_64-linux-gnu/wireshark/plugins/proto_bundle.desc", "rb"))
local data = f:read("*a")
f:close()
assert(pb.load(data))

-- Define protocol and fields
local protobuf_ws = Proto("protobuf_ws", "Protobuf over WebSocket")
local f_type = ProtoField.string("protobuf_ws.type", "Message Type")
protobuf_ws.fields = { f_type }

-- Field extractors
local ws_payload_field = Field.new("websocket.payload")
local ws_mask_field = Field.new("websocket.mask")

-- Helper to determine if it's a request or response
local function is_request()
    local mask = ws_mask_field()
    return mask and tostring(mask) == "True"
end

-- Convert byte array to hex string
local function bytes_to_hex(bytes)
    return (bytes:gsub(".", function(c)
        return string.format("%02x ", string.byte(c))
    end))
end

-- Recursively add fields to Wireshark tree
local function add_fields_to_tree(tree, tbl)
    for k, v in pairs(tbl) do
        if tostring(k):sub(1, 1) ~= "_" then  -- skip internal fields
            if type(v) == "table" then
                local subtree = tree:add(k .. ":")
                add_fields_to_tree(subtree, v)
            elseif type(v) == "string" and #v > 0 and v:match("[^\32-\126]") then
                -- This is probably a raw byte string (non-printable)
                tree:add(k .. ": " .. bytes_to_hex(v))
            else
                tree:add(k .. ": " .. tostring(v))
            end
        end
    end
end

-- Main dissector function
function protobuf_ws.dissector(tvb, pinfo, tree)
    local payload_field = ws_payload_field()
    if not payload_field then return end

    pinfo.cols.protocol = "ProtobufWS"

    local decode_type = is_request() and "request.Request" or "response.Response"
    local subtree = tree:add(protobuf_ws, tvb(), "Decoded Protobuf over WebSocket")
    subtree:add(f_type, decode_type)

    local raw_bytes = payload_field.range:raw()
    local ok, decoded = pcall(pb.decode, decode_type, raw_bytes)
    if ok and decoded then
        local decoded_tree = subtree:add("Decoded Protobuf:")
        add_fields_to_tree(decoded_tree, decoded)
    else
        subtree:add("Decoding failed for: " .. decode_type)
    end
end

register_postdissector(protobuf_ws)

