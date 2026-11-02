<p align="center"><img src="assets/logo-emblem.png" alt="Salalah Vocational College emblem" width="96"></p>

# SVC Exam Portal

An exam invigilation portal for Salalah Vocational College, built on Oracle Database and Oracle APEX. It replaces the Google Sheet used during exams with:

- one sheet per room for the Morning and Afternoon sessions, covering warnings, absentees, invigilators and comments
- a staff chat
- an end-of-day report for the administrator

**Developer:** Ms. Amina Qatan

## What is in this repository

| Path | What it is |
|---|---|
| `index.html` | Interactive preview of the portal. Open it in a browser or publish it with GitHub Pages. |
| `database/svc_exam_portal.sql` | Oracle script (v1.4): tables, views, PL/SQL packages and starting data. |
| `assets/logo-emblem.png` | College emblem used in the top bar. |
| `chat-config.js` | Connects the staff chat to your Firebase project (see "Set up the chat"). |
| `firestore.rules` | Security rules for the chat, to paste into Firebase. |

## Features

- 24 rooms, labs and drawing halls, each with a Morning and an Afternoon sheet
- Exam dropdowns:
  - Exam: Midterm Exam, Final Exam
  - Term: 1, 2, 3
  - Programs: Preparatory, Post-Preparatory (one or both)
  - Month: September to August
  - Academic year: 2026-2027 onwards
- Course dropdown: 114 courses with their codes, grouped by specialization
- Invigilator (1), Invigilator (2) and Floor invigilator dropdowns. The same person can't be chosen twice.
- Warning 1, Warning 2, Warning 3 and Cheating report, with one-tap escalation
- Absentee list, with absent and total counts calculated automatically
- Comment ticks (Copying, Sharing answers, Mobile, Talking) and notes
- Washroom notice in Arabic and English
- Staff chat: staff sign in with Google, and a list shows who is active and in which room
- Five colour themes (Sheet Classic, Khareef Green, Frankincense, Arabian Sea, Slate), custom colours, light and dark mode
- End-of-day report for administrators only:
  - charts and tables
  - downloads as Excel, CSV and an HTML dashboard

## Roles

| Role | What they can do |
|---|---|
| Owner, Administrator | Everything, including the end-of-day report, its downloads and clearing the chat |
| Floor invigilator, Invigilator | Fill in the room sheets and use the chat. The report icon is hidden, and the report page and downloads are locked on the server. |

## Try the preview

- **On your computer:** open `index.html` in a browser.
- **Online with GitHub Pages:**
  1. In the repository, go to Settings › Pages.
  2. Choose Deploy from a branch, branch `main`, folder `/ (root)`, and save.
  3. After a minute the portal is live at `https://<your-username>.github.io/<repository-name>/`.

The GitHub preview runs on its own, without any server:

- Edits stay in the browser until the page is reloaded.
- The **Viewing as** switch in the side menu shows what each role sees.
- The **Chat** icon is in the top bar. It works once you connect it to Firebase (see "Set up the chat"). Until then, the chat panel shows a short setup message.

## Set up the chat (free, about 15 minutes)

The chat on GitHub Pages uses Firebase, Google's free database service.

- Staff sign in with their Google account.
- Only the emails you list can read or post.
- People can delete their own messages. Administrators can delete any message or clear the chat.

1. Go to [console.firebase.google.com](https://console.firebase.google.com) and create a project (for example `svc-exam-portal`). Google Analytics is not needed.
2. Open **Build › Authentication** and click **Get started**. Under **Sign-in method**, turn on **Google**.
3. In **Authentication › Settings › Authorized domains**, click **Add domain** and enter `<your-username>.github.io`.
4. Open **Build › Firestore Database › Create database**. Choose a location near you and start in **production mode**.
5. In **Firestore Database › Rules**, replace everything with the contents of `firestore.rules`, then click **Publish**.
6. In **Firestore Database › Data**, click **Start collection** and name it `config`. Give the first document the ID `access` and add these fields, with all emails in lower case:
   - `staff`, type **array**: each staff member's Google email, including yours
   - `admins`, type **array**: your email, and anyone else who may delete any message
   - `domain`, type **string**, optional: your college email domain (for example `example.edu.om`), to let every account on it in
7. Open **Project settings** (the gear icon). Under **Your apps**, click the web icon `</>` and register an app. Copy the `firebaseConfig` values into `chat-config.js`, following the example in that file, and commit it.
8. Open your GitHub Pages site, tap **Chat**, and sign in with Google.

Good to know:
- **Changing who can use the chat:** to add or remove someone later, edit the `staff` list in `config/access`. No change to the website is needed.
- **Keep emails out of this repository:** keep staff emails in Firebase only, because this repository is public. The values in `chat-config.js` are not passwords; the rules protect the data.
- **Free plan limits:** the chat shows the last 3 days of messages (up to 100). The "active today" list updates when someone signs in or settles on a room. This keeps daily use within Firebase's free Spark plan. If the plan's daily limit is ever reached, the chat pauses until the limit resets.

## Set up the database (Oracle APEX)

Requirements: Oracle Database 19c or later and Oracle APEX 22.2 or later. A free workspace on [apex.oracle.com](https://apex.oracle.com) works.

1. In your APEX workspace, open SQL Workshop › SQL Scripts › Upload. Choose `database/svc_exam_portal.sql`, then Run.
2. Check that your login is the portal owner:
   ```sql
   SELECT * FROM svc_app_users;
   ```
3. Add the other staff with their roles, for example:
   ```sql
   INSERT INTO svc_app_users (app_user, app_role) VALUES ('ALI.R', 'FLOOR_INVIGILATOR');
   ```
4. Follow section 10 at the end of the script to build the APEX pages:
   - room navigation and section tabs
   - colour themes
   - the administrator report
   - the course and staff lists
   - the staff chat (Oracle version)
   - the exam dropdowns

The script can be run again. It drops and recreates only its own objects, so running it again deletes the data in them.

## Data and privacy

The staff and student names in this repository are placeholders (for example "Invigilator 01" and "Sample Student 1"). Real names belong in the Oracle database, not in a public repository.
