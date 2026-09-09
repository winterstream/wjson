-- Benchmark-only loader for lunajson 1.2.3.
-- The benchmark uses only lunajson's encoder and decoder APIs.
local newdecoder = require "lunajson.decoder"
local newencoder = require "lunajson.encoder"

return {
  decode = newdecoder(),
  encode = newencoder(),
}
