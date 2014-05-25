# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$ ->
  tossSheets()
  null

randRange = (zero, nplus1) ->
  diff  = nplus1 - zero
  zero + Math.floor(Math.random() * diff)

tossSheets = () ->
  for i in $('img')
    img = $(i)
    img.css({transform: "rotate(#{randRange(-7, 7)}deg)"})
