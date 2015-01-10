fs = require 'fs'
path = require 'path'
{spawn, exec} = require 'child_process'

# ANSI Terminal Colors.
bold = red = green = reset = ''
unless process.env.NODE_DISABLE_COLORS
  bold  = '\x1B[0;1m'
  red   = '\x1B[0;31m'
  green = '\x1B[0;32m'
  reset = '\x1B[0m'

SOURCEFILES = ['transformer', 'parser', 'serialiser', 'symbols', 'helpers']
TESTFILES = ['test.coffee','output-testcases.txt','eval-testcases.txt']
JSFILES = ['htmlelements.js', 'entitydecode.js', 'stringescape.js']

# Log a message with a color.
log = (message, color, explanation) ->
  console.log color + message + reset + ' ' + (explanation or '')

# Build transformer from source.
build = (cb) ->
  run 'mkdir', ['bin', 'lib'], ->
    compile SOURCEFILES, 'src/', 'lib/', ->
      copy JSFILES, 'src/', 'lib/', cb

copy = (srcFiles, srcDir, destDir, cb) ->
  srcFiles.forEach((filename)->
    run 'cp', [srcDir+filename, destDir+filename]
  )
  cb?()

compile = (srcFiles, srcDir, destDir, cb) ->
  args = [
    '--bare',
    '--output', destDir,
    '--compile'
  ].concat srcFiles.map((filename) -> path.join(srcDir, "#{filename}.coffee"))

  coffee args, cb

# Run CoffeeScript command
coffee = (args, cb) -> run 'coffee', args, cb

run = (executable, args = [], cb) ->
  ###
  try
    proc =         spawn executable, args
    proc.stdout.on 'data', (buffer) -> log buffer.toString(), green
    proc.stderr.on 'data', (buffer) -> log buffer.toString(), red
    proc.on        'exit', (status) ->
  		cb() if typeof cb is 'function'
  catch e
    console.warn('spawn execution failed, exec fallback used', e)
  ###
  command = executable + ' ' + (args || []).join(' ')
  exec command, [], cb

test = -> coffee ['test/test.coffee']

task 'build', 'build cjsx transformer from source', build

task 'test', 'run tests', -> build test

task 'watch', 'watch and build', ->
  SOURCEFILES.forEach (sourcefile) ->
    fs.watchFile "src/#{sourcefile}.coffee", interval: 1000, ->
      build ->
        log 'rebuild complete', bold
  log "watching..." , green

task 'watch:test', 'watch and run tests', ->
  TESTFILES.forEach (testfile) ->
    fs.watchFile "test/#{testfile}", interval: 1000, -> build -> setTimeout(test, 200)
  SOURCEFILES.forEach (sourcefile) ->
    fs.watchFile "src/#{sourcefile}.coffee", interval: 1000, -> build -> setTimeout(test, 200)
  log "watching..." , green
