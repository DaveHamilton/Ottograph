A fix for Ottograph quietly running up Mail's CPU while your Mac sat locked.

- **Mail no longer burns CPU overnight.** With the screen locked, macOS hands Ottograph a distorted view of Mail's windows: each window reads back as Mail itself, which contains itself again. Ottograph's search for compose windows went round in that loop — hundreds of thousands of requests to Mail per check, once a second. Left locked overnight, Mail sat at around 80% CPU, and quitting Ottograph was the only thing that brought it down. Every search now refuses to go round a loop and has a hard size limit, so this can't recur in some other shape either.
- **Ottograph leaves Mail alone when you aren't writing.** It used to check every Mail window once a second whether or not a compose window existed. Now it waits for Mail to say a window opened, came to the front, or changed sender, and with no compose window open it sends Mail nothing at all. While one is open, a slow safety-net check runs and stops the moment the last one closes. The Settings interval only applies while you're composing.

Measured on the Mac that reported it: Mail's main thread went from 54% inside Ottograph's requests to none, locked or unlocked, and Ottograph itself reads 0% when idle. Signatures, auto-Cc, and replies behave as before.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.
