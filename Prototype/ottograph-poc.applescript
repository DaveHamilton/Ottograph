-- Ottograph proof of concept
-- Run this from Script Editor with a Mail compose window open.
-- It reads the From address of the frontmost compose window and applies
-- the mapped signature — the same core trick the menu bar app automates.
--
-- Edit the mapping list below: {alias address, signature name in Mail Settings}

property mappings : {¬
	{"you@example.com", "Signature Name As It Appears In Mail Settings"}, ¬
	{"alias@example.com", "Another Signature Name"}}

tell application "Mail"
	if (count of outgoing messages) = 0 then
		display alert "Ottograph POC" message "Open a compose window in Mail first."
		return
	end if

	set senderText to sender of outgoing message 1

	-- extract the bare address from "Name <address>"
	set theAddress to senderText
	if senderText contains "<" then
		set AppleScript's text item delimiters to "<"
		set theAddress to text item 2 of senderText
		set AppleScript's text item delimiters to ">"
		set theAddress to text item 1 of theAddress
		set AppleScript's text item delimiters to ""
	end if

	repeat with pair in mappings
		if (item 1 of pair as text) is theAddress then
			set message signature of outgoing message 1 to signature (item 2 of pair as text)
			return "Applied signature '" & (item 2 of pair as text) & "' for " & theAddress
		end if
	end repeat

	return "No mapping found for " & theAddress
end tell
