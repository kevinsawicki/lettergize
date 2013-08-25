crypto = require 'crypto'
fs = require 'fs'

Canvas = require 'canvas'
express = require 'express'
request = require 'request'

process.on 'uncaughtException', (error) ->
  console.error 'Uncaught exception', error.stack ? error

app = express()

app.get '*', (request, response) ->
  if src = request.query.src
    fetchImage src, (error, image) ->
      if error?
        response.status(400).send(error.message)
      else
        renderAsciiImage(image, request, response)
  else if emailAddress = request.path[1..]
    fetchAvatar emailAddress, (error, avatar) ->
      if error?
        response.status(400).send(error.message)
      else
        renderAsciiImage(avatar, request, response)
  else
    response.status(400).send('Bad request')

app.listen(process.env.PORT or 3000)

renderAsciiImage = (imageSource, request, response) ->
  image = new Canvas.Image
  image.onerror = (error) ->
    console.error('Image failed to load', error)
    response.status(400).send('Image failed to load')
  image.onload = ->
    canvas = new Canvas(image.width, image.height)
    canvasWidth = canvas.width
    canvasHeight = canvas.height
    context = canvas.getContext('2d')
    context.drawImage(image, 0, 0, canvasWidth, canvasHeight)

    characters = [' ', '.', ':', 'i', '1', 't', 'f', 'L', 'C', 'G', '0', '8', '@']

    imageData = context.getImageData(0, 0, canvasWidth, canvasHeight)
    fontSize = 5
    outputCanvas = new Canvas(canvasWidth * fontSize, canvasHeight * fontSize)
    outputContext = outputCanvas.getContext('2d')
    outputContext.font = "#{fontSize}px monospace"
    lineOffset = 0
    contrast = parseInt(request.query.contrast) or 128
    for y in [0...canvasHeight] by 2
      line = ''
      for x in [0...canvasWidth]
        offset = (y * canvasWidth + x) * 4
        color = color = getColorAtOffset(imageData.data, offset)
        index = getIndexForColor(color, contrast, characters.length)
        line += characters[index]

      outputContext.fillText(line, 0, lineOffset)
      lineOffset += fontSize

    response.set('Content-Type', 'image/png')
    response.status(200).send(outputCanvas.toBuffer())
  image.src = imageSource

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
