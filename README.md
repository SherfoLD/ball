![Screen recording of a ball bouncing](Recording.gif)

# Ball

It's a little ball that lives in your dock. You can drag it and it'll bounce around the screen. You can also swipe on it with two fingers. It comes in red. You can flick it, bounce it, try to make it hit the corner, see how many times it can bounce, count how many times it hits the wall, and more. It's a ball. It's fun. It's a ball.

**Download in [Releases](https://github.com/nate-parrott/ball/releases)**

## Credits

It's inspired by [Nate Heagy's](https://heagy.com/) widget for the OS X Dashboard, which I remember fondly because someone put it on our class [eMac](https://en.wikipedia.org/wiki/EMac) in fifth grade. It was a lot bouncier and come in more colors, but it didn't go in the dock!

Credit also goes to Wessley Roche, who made this [little Gist](https://gist.github.com/wonderbit/c8896ff429a858021a7623f312dcdbf9) explaining how to get the position of the dock. I've [extended this](https://github.com/nate-parrott/ball/blob/main/Ball/DockUtils.swift#L65) to try to estimate the position of the app's dock icon when it's clicked, so the ball can animate out of it. 

Balls bounce off the Dock and cannot be dragged into its reserved screen area. Dock bounds refresh while the simulation runs, supporting bottom, left, and right positions. When macOS exposes a tight Dock window, collisions use those bounds; otherwise, they protect the full strip reserved by `NSScreen.visibleFrame`. The app keeps its existing sandbox and needs no extra permissions. Magnified icons and temporary auto-hide reveals can extend beyond the bounds macOS reports, so the fallback cannot cover those reliably.

Run `Tests/run.sh` on macOS for the headless Dock geometry and physics regression checks. The harness compiles the production solver with a rendering-free ball model; build the app with Xcode to check the SpriteKit integration.

## Final words

I hope you enjoy this little ball.
