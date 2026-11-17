import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum CloudSaveStatus {
  cloudVerified,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
}

class CloudSaveResult {
  final CloudSaveStatus status;
  final String roundId;
  final String message;

  const CloudSaveResult({
    required this.status,
    required this.roundId,
    required this.message,
  });
}

class CloudAttemptService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String createRoundId(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .doc()
        .id;
  }

  DocumentReference<Map<String, dynamic>> _attemptReference(
    String uid,
    String roundId,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .doc(roundId);
  }

  Map<String, dynamic> _expectedFields(int correctCount) {
    return {
      'schemaVersion': 1,
      'variant': 'A',
      'categoryId': 9,
      'questionCount': 10,
      'correctCount': correctCount,
    };
  }

  bool _matchesExpected(Map<String, dynamic> data, int correctCount) {
    final expected = _expectedFields(correctCount);

    if (data.length != 6) return false;

    for (final entry in expected.entries) {
      if (data[entry.key] != entry.value) {
        return false;
      }
    }

    return data['submittedAt'] is Timestamp;
  }

  CloudSaveResult _result(
    CloudSaveStatus status,
    String roundId,
    String message,
  ) {
    return CloudSaveResult(status: status, roundId: roundId, message: message);
  }

  bool _isCurrentUser(String uid) {
    return FirebaseAuth.instance.currentUser?.uid == uid;
  }

  Future<CloudSaveResult> submitAttempt({
    required String uid,
    required String roundId,
    required int correctCount,
    bool simulateLostAcknowledgment = false,
  }) async {
    if (correctCount < 0 || correctCount > 10) {
      throw ArgumentError('Score must be between 0 and 10.');
    }

    if (!_isCurrentUser(uid)) {
      return _result(
        CloudSaveStatus.verificationUnavailable,
        roundId,
        'The signed-in user has changed.',
      );
    }

    final reference = _attemptReference(uid, roundId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);

        if (!_isCurrentUser(uid)) {
          throw StateError('The signed-in user has changed.');
        }

        if (snapshot.exists) {
          final existing = snapshot.data();

          if (existing == null || !_matchesExpected(existing, correctCount)) {
            throw StateError('Round ID collision or mismatched saved attempt.');
          }

          return;
        }

        transaction.set(reference, {
          ..._expectedFields(correctCount),
          'submittedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!_isCurrentUser(uid)) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'The signed-in user has changed.',
        );
      }

      // Development-only lost acknowledgment simulation.
      // The write succeeds, but the app reports uncertainty.
      if (simulateLostAcknowledgment) {
        return _result(
          CloudSaveStatus.saveUnknown,
          roundId,
          'Simulated lost acknowledgment. '
          'Retry using the same Round ID.',
        );
      }

      return await verifyAttempt(
        uid: uid,
        roundId: roundId,
        correctCount: correctCount,
      );
    } on FirebaseException catch (error) {
      if (!_isCurrentUser(uid)) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'The signed-in user has changed.',
        );
      }

      if (error.code == 'permission-denied') {
        return _result(
          CloudSaveStatus.permissionDenied,
          roundId,
          'Firestore permission denied.',
        );
      }

      return _result(
        CloudSaveStatus.saveUnknown,
        roundId,
        'Save could not be confirmed (${error.code}). '
        'Reconnect and retry the same Round ID.',
      );
    } catch (error) {
      return _result(
        CloudSaveStatus.saveUnknown,
        roundId,
        'Save could not be confirmed: $error',
      );
    }
  }

  // Recovery method:
  // First check whether the original write already succeeded.
  // If it did not, retry the transaction with the SAME Round ID.
  Future<CloudSaveResult> retrySaveAndVerify({
    required String uid,
    required String roundId,
    required int correctCount,
  }) async {
    if (correctCount < 0 || correctCount > 10) {
      throw ArgumentError('Score must be between 0 and 10.');
    }

    if (!_isCurrentUser(uid)) {
      return _result(
        CloudSaveStatus.verificationUnavailable,
        roundId,
        'The signed-in user has changed.',
      );
    }

    final reference = _attemptReference(uid, roundId);

    try {
      // A server-only read avoids trusting cached data.
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );

      if (!_isCurrentUser(uid)) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'The signed-in user has changed.',
        );
      }

      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'A confirmed server read is not available.',
        );
      }

      if (snapshot.exists) {
        final data = snapshot.data();

        if (data == null || !_matchesExpected(data, correctCount)) {
          return _result(
            CloudSaveStatus.verificationUnavailable,
            roundId,
            'Existing server record does not match this round.',
          );
        }

        return _result(
          CloudSaveStatus.cloudVerified,
          roundId,
          'Cloud verified! Score: $correctCount/10',
        );
      }

      // The server confirmed that this document is absent.
      // Retry the original write without creating a new ID.
      return await submitAttempt(
        uid: uid,
        roundId: roundId,
        correctCount: correctCount,
      );
    } on FirebaseException catch (error) {
      return _result(
        error.code == 'permission-denied'
            ? CloudSaveStatus.permissionDenied
            : CloudSaveStatus.verificationUnavailable,
        roundId,
        'Recovery failed: ${error.code}',
      );
    } catch (error) {
      return _result(
        CloudSaveStatus.verificationUnavailable,
        roundId,
        'Recovery unavailable: $error',
      );
    }
  }

  Future<CloudSaveResult> verifyAttempt({
    required String uid,
    required String roundId,
    required int correctCount,
  }) async {
    if (!_isCurrentUser(uid)) {
      return _result(
        CloudSaveStatus.verificationUnavailable,
        roundId,
        'The signed-in user has changed.',
      );
    }

    try {
      final snapshot = await _attemptReference(
        uid,
        roundId,
      ).get(const GetOptions(source: Source.server));

      if (!_isCurrentUser(uid)) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'The signed-in user has changed.',
        );
      }

      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'A confirmed server read is not available.',
        );
      }

      final data = snapshot.data();

      if (!snapshot.exists ||
          data == null ||
          !_matchesExpected(data, correctCount)) {
        return _result(
          CloudSaveStatus.verificationUnavailable,
          roundId,
          'The server record is missing or does not match.',
        );
      }

      return _result(
        CloudSaveStatus.cloudVerified,
        roundId,
        'Cloud verified! Score: $correctCount/10',
      );
    } on FirebaseException catch (error) {
      return _result(
        error.code == 'permission-denied'
            ? CloudSaveStatus.permissionDenied
            : CloudSaveStatus.verificationUnavailable,
        roundId,
        'Server verification failed: ${error.code}',
      );
    } catch (error) {
      return _result(
        CloudSaveStatus.verificationUnavailable,
        roundId,
        'Server verification unavailable: $error',
      );
    }
  }
}
