$ ->
  # tossSheets()
  null

randRange = (zero, nplus1) ->
  diff  = nplus1 - zero
  zero + Math.floor(Math.random() * diff)

tossSheets = () ->
  mama  = $($('.posts')[0])
  marq  = $('<div class="gallery"></div>')
  dem   = $('.post')
  mama.before marq if dem.length > 1
  for p in dem
    post  = $(p)
    tit   = $($('.mainh a', post)[0]).text()
    stit  = $($('.sub', post)[0]).text()
    for eikone in $('img', post)
      outos = $(eikone)
      cap   = outos.attr('alt') || "#{tit}: #{stit}"
      intro = ''
      cred  = ''
      pcs   = cap.split ':', 2
      if pcs.length < 2
        pcs = cap.split '.', 2
        if pcs.length > 1
          pcs[0] = pcs[0]
      if pcs.length > 1
        intro = pcs[0]
        cap   = pcs[1]
      # Process cred later. TODO.
      img   = "<div class=\"imgframe\"><img class=\"neaeikone\" src=\"#{outos.attr('src')}\" /><div class='caption'><div class='intro'>#{intro}</div>#{cap}<div class='credits'>#{cred}</div></div></div>"
      marq.append $(img)
      outos.closest('.copy').before $("<div class='gallery'>#{img}</div>")
      outos.hide()
