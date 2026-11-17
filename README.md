# ICA 16 — Cloud Quiz (Class A)

A Flutter-based General Knowledge quiz application built for CSC 4360 Mobile App Development at Georgia State University.

The app uses the Open Trivia Database API to load questions, Firebase Authentication to manage users, and Cloud Firestore to securely save and verify quiz attempts.

## Features

- Email and password sign-in using Firebase Authentication
- 10 multiple-choice General Knowledge questions per round
- Questions retrieved from the Open Trivia Database (OpenTDB)
- Randomized answer choices and HTML-decoded question text
- Quiz scoring and answer review
- Replay functionality for additional rounds
- Cloud storage of completed attempts using Firestore
- Server-side verification of saved attempts
- Retry and recovery handling for network interruptions
- Firestore security rules restricting access to the authenticated owner

## Technologies Used

- Flutter and Dart
- Firebase Authentication
- Cloud Firestore
- Open Trivia Database API
- HTTP package
- HTML Unescape package

## How the App Works

1. The user signs in with an email and password.
2. The app requests 10 easy General Knowledge questions from OpenTDB.
3. The user answers the questions and reviews their results.
4. The user submits the completed quiz.
5. Firestore stores the attempt under the authenticated user's UID.
6. The app reads the saved attempt from the server to verify it.
7. A successful verification displays the Cloud Verified status.

Each quiz round has its own unique round ID to prevent duplicate submissions.

## Quiz API

The application uses this OpenTDB endpoint:

`https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple`

The app requests exactly 10 easy, multiple-choice General Knowledge questions.

## Firestore Data Structure

Quiz attempts are saved at:

`users/{uid}/attempts/{roundId}`

Each attempt contains exactly six fields:

| Field | Description |
|---|---|
| schemaVersion | Schema version, set to 1 |
| variant | Assignment variant, set to A |
| categoryId | General Knowledge category ID, set to 9 |
| questionCount | Number of questions, set to 10 |
| correctCount | Number of correct answers, from 0 to 10 |
| submittedAt | Firestore server timestamp |

The app uses a Firestore transaction to avoid overwriting existing attempts. It also performs a server-only read to confirm that the attempt was saved successfully.

## Security

Firebase Authentication identifies the current user.

Firestore security rules allow users to read and create only their own valid quiz attempts. Existing attempts cannot be updated or deleted.

The rules are included in `firestore.rules`.

No test-user passwords or private service-account credentials are included in this repository.

## Error Handling

The application handles several possible errors, including:

- Authentication errors
- Trivia API request failures
- Network timeouts
- Offline submission attempts
- Firestore permission errors
- Unavailable cloud verification
- Uncertain save outcomes

The Retry Save & Verify feature helps recover an attempt after a network interruption without creating a new round ID.

## Running the Project

Requirements:

- Flutter SDK
- Android device or emulator
- Firebase project configured for the application
- Internet connection

Clone the repository:

```bash
git clone https://github.com/eyobedmerhawi/ica16-cloud-quiz.git
cd ica16-cloud-quiz
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

The included Firebase configuration is associated with the original project. Running a separate deployment requires appropriate Firebase configuration and permissions.

## Testing

The application was tested using two Firebase Authentication accounts to verify that quiz attempts are stored under separate user IDs.

Testing also included:

- Completing and submitting quiz rounds
- Checking saved Firestore documents
- Confirming the Cloud Verified state
- Testing offline submission and recovery after reconnecting
- Checking that Firestore rules reject cross-user reads and updates to existing attempts
- Building and installing a release APK on an Android device

Additional test evidence is documented in the assignment submission.

## Release APK

The Android release APK was built using:

```bash
flutter build apk --release
```

Submission filename:

`ICA16_A_Eyobed_Gebregziabher.apk`

The APK is submitted separately from the GitHub repository.

## Project Structure

```text
lib/
  main.dart
  trivia_service.dart
  cloud_attempt_service.dart
  firebase_options.dart

android/
ios/
firestore.rules
pubspec.yaml
README.md
```

## Author

Eyobed Gebregziabher

Georgia State University  
CSC 4360 — Mobile App Development  
In-Class Activity 16 — Class A: General Knowledge  
November 2026
