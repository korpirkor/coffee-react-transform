
{last, find} = require './helpers'

{ SourceNode } = require('source-map')
$ = require './symbols'

stringEscape = require './stringescape'

entityDecode = require './entitydecode'

module.exports = exports = serialise = (parseTree, filename) ->
  new Serialiser(filename).serialise(parseTree)

class Serialiser
  constructor: (@filename) ->

  serialise: (parseTree) ->
    if parseTree.children and
    parseTree.children.length and
    parseTree.children[0].type is $.CJSX_PRAGMA
      @domObject = parseTree.children[0].value
    else
      @domObject = 'React.DOM'

    domObjectParts = @domObject.split('.')
    if domObjectParts.length > 0 and domObjectParts[0] isnt ''
      @reactObject = domObjectParts[0]
    else
      @reactObject = 'React'

    result = @serialiseNode(parseTree).toStringWithSourceMap()

    if @filename
      result.code +
        "\n# //# sourceMappingURL=data:application/json;base64," +
        (new Buffer(result.map.toString()).toString('base64'))
    else
      result.code

  serialiseNode: (node) ->
    unless nodeSerialisers[node.type]?
      throw new Error("unknown parseTree node type #{node.type}")

    serialised = nodeSerialisers[node.type].call(this, node)


    unless node.line?
      return serialised

    return new SourceNode(node.line, node.column, @filename, serialised)

  serialiseSpreadAndPairAttributes: (children) ->
    assigns = []
    pairAttrsBuffer = []

    flushPairs = =>
      if pairAttrsBuffer.length
        serialisedChild = @serialiseAttributePairs(pairAttrsBuffer)
        assigns.push(serialisedChild) if serialisedChild # skip null
        pairAttrsBuffer = [] # reset buffer

    if firstNonWhitespaceChild(children)?.type is $.CJSX_ATTR_SPREAD
      assigns.push('{}')

    for child, childIndex in children
      if child.type is $.CJSX_ATTR_SPREAD
        flushPairs()
        assigns.push(child.value)
      else
        pairAttrsBuffer.push(child)

      flushPairs()

    "React.__spread(#{joinList(assigns)})"

  serialiseAttributePairs: (children) ->
    # whitespace (particularly newlines) must be maintained
    # to ensure line number parity

    # sort children into whitespace and semantic (non whitespace) groups
    # this seems wrong :\
    [whitespaceChildren, semanticChildren] = children.reduce((partitionedChildren, child) ->
      if child.type is $.CJSX_WHITESPACE
        partitionedChildren[0].push child
      else
        partitionedChildren[1].push child
      partitionedChildren
    , [[],[]])

    indexOfLastSemanticChild = children.lastIndexOf(last(semanticChildren))

    isBeforeLastSemanticChild = (childIndex) ->
      childIndex < indexOfLastSemanticChild

    if semanticChildren.length
      serialisedChildren = for child, childIndex in children
        serialisedChild = @serialiseNode child
        if child.type is $.CJSX_WHITESPACE
          if containsNewlines(serialisedChild.toString())
            if isBeforeLastSemanticChild(childIndex)
              # escaping newlines within attr object helps avoid
              # parse errors in tags which span multiple lines
              serialisedChild.replaceRight('\n',' \\\n')
            else
              # but escaped newline at end of attr object is not allowed
              serialisedChild
          else
            null # whitespace without newlines is not significant
        else if isBeforeLastSemanticChild(childIndex)
          serialisedChild+', '
        else
          serialisedChild

      '{'+serialisedChildren.join('')+'}'
    else
      null

genericBranchSerialiser = (node) ->
  new SourceNode(node.line, node.column, @filename, '')
      .add(node.children.map((child) => @serialiseNode child))

genericLeafSerialiser = (node) -> node.value

tagConvention = /^[a-z]|\-/

nodeSerialisers =
  ROOT: genericBranchSerialiser

  CJSX_PRAGMA: -> null

  CJSX_EL: (node) ->
    serialisedChildren = []
    accumulatedWhitespace = ''

    for child in node.children
      serialisedChild = @serialiseNode child
      if child? # filter empty text nodes
        if WHITESPACE_ONLY.test serialisedChild
          accumulatedWhitespace += serialisedChild
        else
          serialisedChildren.push(accumulatedWhitespace + serialisedChild)
          accumulatedWhitespace = ''

    if serialisedChildren.length
      serialisedChildren[serialisedChildren.length-1] += accumulatedWhitespace
      accumulatedWhitespace = ''

    # from react-tools/vendor/fbtransform/transforms/react.js
    # Identifiers with lower case or hypthens are fallback tags (strings).
    if tagConvention.test(node.value)
      element = '"'+node.value+'"'
    else
      element = node.value
    "#{@reactObject}.createElement(#{element}, #{joinList(serialisedChildren)})"

  CJSX_ESC: (node) ->
    childrenSerialised = node.children
      .map((child) => @serialiseNode child)
      .join('')
    '('+childrenSerialised+')'

  CJSX_ATTRIBUTES: (node) ->
    if node.children.some((child) -> child.type is $.CJSX_ATTR_SPREAD)
      @serialiseSpreadAndPairAttributes(node.children)
    else
      @serialiseAttributePairs(node.children) or 'null'

  CJSX_ATTR_PAIR: (node) ->
    node.children
      .map((child) => @serialiseNode child)
      .join(': ')

  CJSX_ATTR_SPREAD: (node) ->
    node.value

  # leaf nodes
  CS: genericLeafSerialiser
  CS_COMMENT: genericLeafSerialiser
  CS_HEREDOC: genericLeafSerialiser
  CS_STRING: genericLeafSerialiser
  CS_REGEX: genericLeafSerialiser
  CS_HEREGEX: genericLeafSerialiser
  JS_ESC: genericLeafSerialiser
  CJSX_WHITESPACE: genericLeafSerialiser

  CJSX_TEXT: (node) ->
    # trim whitespace only if it includes a newline
    text = node.value
    if containsNewlines(text)
      if WHITESPACE_ONLY.test text
        text
      else
        # this is not very efficient
        leftSpace = text.match TEXT_LEADING_WHITESPACE
        rightSpace = text.match TEXT_TRAILING_WHITESPACE

        if leftSpace
          leftTrim = text.indexOf('\n')
        else
          leftTrim = 0

        if rightSpace
          rightTrim = text.lastIndexOf('\n')+1
        else
          rightTrim = text.length

        trimmedText = text.substring(leftTrim, rightTrim)
        # decode html entities to chars
        # escape string special chars except newlines
        # output to multiline string literal for line parity
        escapedText = stringEscape(entityDecode(trimmedText), preserveNewlines:  true)
        '"""'+escapedText+'"""'

    else
      if text == ''
        null # this text node will be omitted
      else
        # decode html entities to chars
        # escape string special chars
        '"'+stringEscape(entityDecode(text))+'"'

  CJSX_ATTR_KEY: genericLeafSerialiser
  CJSX_ATTR_VAL: genericLeafSerialiser

firstNonWhitespaceChild = (children) ->
  find.call children, (child) ->
    child.type isnt $.CJSX_WHITESPACE

containsNewlines = (text) -> text.indexOf('\n') > -1

joinList = (items) ->
  output = items[items.length-1]
  i = items.length-2

  while i >= 0
    if output.charAt(0) is '\n'
      output = items[i]+','+output
    else
      output = items[i]+', '+output
    i--
  output


SPACES_ONLY = /^\s+$/

WHITESPACE_ONLY = /^[\n\s]+$/

# leading and trailing whitespace which contains a newline
TEXT_LEADING_WHITESPACE = /^\s*?\n\s*/
TEXT_TRAILING_WHITESPACE = /\s*?\n\s*?$/

exports.Serialiser = Serialiser
exports.nodeSerialisers = nodeSerialisers
