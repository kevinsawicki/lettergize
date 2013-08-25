crypto = require 'crypto'
fs = require 'fs'
path = require 'path'

async = require 'async'
Canvas = require 'canvas'
express = require 'express'
request = require 'request'

process.on 'uncaughtException', (error) ->
  console.error 'Uncaught exception', error.stack ? error

app = express()

app.get '*', (request, response) ->
  if src = request.query.src
    fetchImage src, (error, image) ->
      renderImage(error, image, request, response)
  else if emailAddress = request.path[1..]
    fetchAvatar emailAddress, (error, avatar) ->
      renderImage(error, avatar, request, response)
  else
    response.status(400).send('Bad request')

app.listen(process.env.PORT or 3000)

renderImage = (error, image, request, response) ->
  if error?
    response.status(400).send(error.message)
  else
    if request.query.type is 'emoji'
      renderEmojiImage(image, request, response)
    else
      renderAsciiImage(image, request, response)

renderAsciiImage = (imageSource, request, response) ->
  createImage imageSource, (error, image) ->
    if error?
      console.error('Image failed to load', error)
      response.status(400).send('Image failed to load')
    else
      canvasWidth = parseInt(request.query.width) or image.width
      canvasHeight = parseInt(request.query.height) or image.height
      canvas = new Canvas(canvasWidth, canvasHeight)
      context = canvas.getContext('2d')
      context.drawImage(image, 0, 0, canvasWidth, canvasHeight)

      if request.query.type is 'octicons'
        characters = [
          ' '
          '\uf01f' # commit
          '\uf015' # tag
          '\uf020' # branch
          '\uf009' # pull request
          '\uf026' # issue opened
          '\uf04e' # eye
          '\uf069' # beer
          '\uf02b' # comment
          '\uf0b2' # squirrel
          '\uf02a' # start
          '\uf008' # octocat
        ]
        fontSize = 12
        outputCanvas = new Canvas(canvasWidth * fontSize, canvasHeight * fontSize)
        outputContext = outputCanvas.getContext('2d')
        outputContext.font = "#{fontSize}px Octicons"
      else
        characters = [' ', '.', ':', 'i', '1', 't', 'f', 'L', 'C', 'G', '0', '8', '@']
        fontSize = 5
        outputCanvas = new Canvas(canvasWidth * fontSize, canvasHeight * fontSize)
        outputContext = outputCanvas.getContext('2d')
        outputContext.font = "#{fontSize}px monospace"

      imageData = context.getImageData(0, 0, canvasWidth, canvasHeight)
      rowOffset = 0
      columnOffset = 0
      contrast = parseInt(request.query.contrast) or 128
      for y in [0...canvasHeight] by 2
        columnOffset = 0
        for x in [0...canvasWidth]
          offset = (y * canvasWidth + x) * 4
          color = getColorAtOffset(imageData.data, offset)
          index = getIndexForColor(color, contrast, characters.length)
          outputContext.fillText(characters[index], columnOffset, rowOffset)
          columnOffset += fontSize

        rowOffset += fontSize

      response.set('Content-Type', 'image/png')
      response.status(200).send(outputCanvas.toBuffer())


createImage = (source, callback) ->
  image = new Canvas.Image
  image.onerror = (error) -> callback(error)
  image.onload = -> callback(null, image)
  image.src = source

loadEmojiImages = (emojis, callback) ->
  emojiImages = []
  loadOperations = []
  for emoji in emojis
    do (emoji) ->
      loadOperations.push (callback) ->
        source = fs.readFileSync(path.join(__dirname, '..', 'emojis', "#{emoji}.png"))
        createImage source, (error, image) ->
          emojiImages.push(image) unless error?
          callback(error)

  async.waterfall loadOperations, (error) ->
    if error?
      callback(error)
    else
      callback(null, emojiImages)

renderEmojiImage = (imageSource, request, response) ->
  createImage imageSource, (error, image) ->
    if error?
      console.error('Image failed to load', error)
      response.status(400).send('Image failed to load')
    else
      canvasWidth = parseInt(request.query.width) or image.width
      canvasHeight = parseInt(request.query.height) or image.height
      canvas = new Canvas(canvasWidth, canvasHeight)
      context = canvas.getContext('2d')
      context.drawImage(image, 0, 0, canvasWidth, canvasHeight)

      emojis = [
        'trollface'
        'cloud'
        'zap'
        'sheep'
        'punch'
        'pear'
        'shipit'
        'fire'
        'metal'
        'heart'
        'suspect'
        'gem'
        'poop'
      ]
      loadEmojiImages emojis, (error, emojiImages) ->
        if error?
          response.status(400).send('Emojis failed to load')
        else
          imageData = context.getImageData(0, 0, canvasWidth, canvasHeight)
          emojiSize = parseInt(request.query.emojiSize) or 10
          outputCanvas = new Canvas(canvasWidth * emojiSize, canvasHeight * emojiSize)
          outputContext = outputCanvas.getContext('2d')
          rowOffset = 0
          contrast = parseInt(request.query.contrast) or 128
          for y in [0...canvasHeight] by 2
            columnOffset = 0
            for x in [0...canvasWidth]
              offset = (y * canvasWidth + x) * 4
              color = getColorAtOffset(imageData.data, offset)
              index = getIndexForColor(color, contrast, emojis.length)
              outputContext.drawImage(emojiImages[index], columnOffset, rowOffset, emojiSize, emojiSize)
              columnOffset += emojiSize

            rowOffset += emojiSize

          response.set('Content-Type', 'image/png')
          response.status(200).send(outputCanvas.toBuffer())

fetchImage = (url, callback) ->
  options = {url, encoding: null}
  request options, (error, response, body) ->
    if not error and response.statusCode is 200
      callback(null, body)
    else
      callback(error ? new Error("Unexpected status code: #{response.statusCode}"))

fetchAvatar = (emailAddress, callback) ->
  addressHash = crypto.createHash('md5').update(emailAddress).digest('hex')
  fetchImage("http://www.gravatar.com/avatar/#{addressHash}?s=400&d=404", callback)

getIndexForColor = (color, contrast, numberOfIndices) ->
  contrastFactor = (259 * (contrast + 255)) / (255 * (259 - contrast))

  contrastedColor =
    red: clipRgbValue(Math.floor((color.red - 128) * contrastFactor) + 128)
    green: clipRgbValue(Math.floor((color.green - 128) * contrastFactor) + 128)
    blue: clipRgbValue(Math.floor((color.blue - 128) * contrastFactor) + 128)
    alpha: color.alpha

  brightness = (0.299 * contrastedColor.red + 0.587 * contrastedColor.green + 0.114 * contrastedColor.blue) / 255

  (numberOfIndices - 1) - Math.round(brightness * (numberOfIndices - 1))

getColorAtOffset = (data, offset) ->
  red: data[offset]
  green: data[offset + 1]
  blue: data[offset + 2]
  alpha: data[offset + 3]

clipRgbValue = (rgbValue) -> Math.max(0, Math.min(255, rgbValue))
