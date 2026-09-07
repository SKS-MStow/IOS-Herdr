# Reading sessions and sending photos

In a session, **Pause** holds the current terminal screen while you read.
**Resume** returns to live output. The **aA** menu offers monospaced text,
following the latest output, the full project folder and manual refresh.
Output is the current terminal screen, not a complete conversation transcript.
The larger body text wraps to the phone width. Terminal keys are in the **+** menu.

Tap **+ → Photo library** or **Image from Files**, choose up to three images,
add a message and send. Photos work with Codex and Claude. Each preview has a
remove button. Photos are unavailable while responding to an approval question;
answer that question first. No camera capture or general document upload is
included in this version; existing photos and image files are supported.

Images are converted on the phone to JPEG, oriented correctly, stripped of
original metadata and reduced to at most 2400 pixels on the longest edge and
3 MB each. Unsent photo drafts stay in the app sandbox, excluded from backups.
The authenticated controller uploads each image before submitting a prompt.
The prompt asks the agent to open the uploaded image using its image-reading
tool. The agent's own tool permissions still apply.

Mac files live beside the controller database in `attachments/`. Windows files
live in `%LOCALAPPDATA%\HerdrShared\attachments`. The worker transport uses the
SSH target already saved in Herdr's machine list, a fixed PowerShell receiver,
controller-generated filenames and SHA-256 verification. Existing workers need
no binary update. Other remote operating systems are not supported by this
receiver yet.

Uploads never execute terminal input. Repeating an upload is safe; submitting
its prompt uses the existing persisted command receipt, so an uncertain prompt
is never replayed automatically. Attachments belong to the paired device and
terminal identity. They cannot be reused by another phone or session. Uploads
are limited to 12/minute per device; retained controller images are capped at
100 MB. A full store rejects new images with a clear error. Files are retained
for agents to revisit; there is no automatic expiry. Remove old files from both
controller and worker attachment directories when no longer needed.

## Verification

The isolated live check uploaded a synthetic image to Mac/Codex and Windows/
Claude. Both identified the image's purple triangle and yellow circle. Upload
hashes were verified; replaying the prompt request returned its receipt. Only
temporary QA workspaces were closed, and pre-existing agent identities were
preserved. Native checks cover image conversion, draft persistence, the system
photo picker, removal controls, reading controls and disabled demo commands.
