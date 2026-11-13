Issues I've found during testing

- [x] There is some kind of dark border on the bottom, remove it.
- [x] Add more spacing between the progress,
      1st set of buttons and the 2nd set of buttons - you can check the docs/design-2.png for reference.
- [x] The progress dot should have a dark border and not completely part of the progress bar - check reference design (reverted on request: back to the glowing accent dot)
- [x] Prev song is not working the same as Spotify, if I listen to three sengs in a row and click prev, my prev song is none of the 2 I've already listened to, check the logic.
- [ ] arrow down should switch to the home page of the app (waits for the home page)
- [ ] we need to think of a home page for the app (skipped for now)
- [x] when i go in Library and then select a playlist, a back button in the top bar shows that does the same think as the back button on the library - remove it, I don't want any buttons in the top bar, only the header
- [x] lets implement bottom nav bar that will include home, playing, library and search buttons each with their corresponding pages. (tried, then removed on request)
- [x] Add hover effect to the buttons - icon buttons should become white (they have less opacity now, make it full on hover)
- [x] On the play/pause button the hover should be smooth, now it's instantly switched (only the press effect is smooth)
- [x] also when I click somewhere on the progress bar, make the progress smoothly move to the selected point, not instantly go to there (same as the volume progress bar, actually if we can make the design the as the volume progress bar just arched like the current playback progress bar)
- [x] on the dots top right menu, also add the version of the Aural app, read it from somewhere, make it 0.0.1.0 for now
- [x] are we taking into consideration the new liquid glass intensity setting from MacOS 27?

NEW:

1. [x] Liked songs listing at the end the last result is almost reaching the end of the window, we need some padding-bottom on there.
2. [x] On the songs listing we need some padding-right as the border bottom of each song listing is reaching the end of the right side.
3. [x] When I click on a song, it starts playing but I'm not redirected to the Now playing (home screen)
4. [x] enhance the playlists listing items to be more inline with the iOS design
5. [x] enhance the songs listing items to be more inline with the iOS design
6. [x] enhance the albums listing items to be more inline with the iOS design
7. [x] enhance the search songs listing items to be more inline with the iOS design
8. [x] top bar when I hover on the dots icon, a background with border radius shows, that should not be the case - reduce the initial padding of the dots and when hovered, make it opacity 1 - basicly make it like the rest of the controls
9. [x] in the top bar settings dots - remove the Go to album option and add the options that the user can edit - API keys, client IDs and what not
10. [x] make the progress bar of the songs even less border-width
11. [x] Also where are the icons coming from, can we use different ones?

LATEST:

1. [x] When I go inside a playlist/album it's not smoothly switching the screen, it's just instantly shows.
2. [x] Dividers in the search - Songs, Artists and so on need more padding on the left and right to match the rest of the app paddings
3. [x] Also lists after every divider in the search needs padding-top as it's super close to the divider name
4. [x] Remove the border bottom of the dividers in the search results
5. [x] Rework the play/pause button, play and shuffle buttons inside the other pages to use the native Liquid Glass button that Apple are using - not some custom one, like it is now.
6. [x] In the onboarding use liquid glass native buttons for both submit (with peach color) and cancel (with default transparent liquid glass button)
7. [x] When closing the ADD YOUR API screen, the Continue button looks like it moves down and fades out, it should not move down, it should just fade out.
8. [x] When inside a playlist/album, screen instantly snaps to the playlist/album listing page and moves to the selected screen, that should not be the case, show the newly selected screen and then reset to playlist/album listing page, because it looks super glitchy now and it's visible.
9. [x] Show songs count and listening time (the same as in Spotify) in album/playlist page.
10. [x] Onboarding content should be centered vertically, but keep the buttons on the bottom of the app.
11. [x] When I switch the song, the play/pause button switches it state and glitches, same goes for the heart icon - when I'm playing songs from my Liked playlists and I switch them one after another, the heart is unfilled and then instantly is filled, same goes for the play/pause button, if the play is enabled (pause icon shown) and I click next song, the button goes to play icon and instantly switches back to pause icon.
12. [x] Switch the places of replay icon and heart icon.
13. [x] Switch the places of shuffle and search icon.
14. [x] heart icon have no hover - use the same effect as we do on the other icons - reduce the default opacity and when hovered, we make it opacity: 1
15. [x] If the progress bar is at some point and I click next arrow, it glitches and moves back to the start, can we refine that reset as it's super glitchy right now.
16. [x] make the song progress animation a little faster.
17. [x] Heart icon should be a + which should function as Add to playlist, not just add to Liked. (Done as Spotify's + / check for Liked Songs only; adding to playlists dropped to keep Aural lightweight.)
18. [x] Add a tooltip on every icon on hover
19. [x] Playlists and albums should have Add to Library, same as on Spotify, so they can be saved for later listening (next to the shuffle and play button on their corresponding pages)
20. [x] Is the phone pairing really necessary, can we skip that step? — Answer: yes, once. Soloist has no login of its own; Spotify only signs it in when the device is picked in an official Spotify app (Connect). The session is then stored and restored on every launch, so the step never appears again unless the pairing is lost. There is no API to skip it.
