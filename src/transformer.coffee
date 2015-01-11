
Parser = require './parser'
serialise = require './serialiser'

module.exports.transform = (code, opts = {}) ->
  tree = (new Parser().parse(code, opts))
  serialise(tree, opts.filename)
