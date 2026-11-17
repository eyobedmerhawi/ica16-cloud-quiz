import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'cloud_attempt_service.dart';
import 'firebase_options.dart';
import 'trivia_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CloudQuizApp());
}

class CloudQuizApp extends StatelessWidget {
  const CloudQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICA 16 Cloud Quiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return const Scaffold(
              body: Center(
                child: Text('Authentication unavailable. Restart the app.'),
              ),
            );
          }
          final user = snapshot.data;
          return user == null
              ? const SignInScreen()
              : QuizScreen(key: ValueKey(user.uid), user: user);
        },
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;

  Future<void> _signIn() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (error.code) {
          'invalid-email' => 'Please enter a valid email address.',
          'invalid-credential' => 'Incorrect email or password.',
          'user-disabled' => 'This account has been disabled.',
          'too-many-requests' => 'Too many attempts. Try again later.',
          'network-request-failed' => 'Check your internet connection.',
          _ => 'Sign-in failed: ${error.message ?? error.code}',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Quiz')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.quiz_outlined,
                    size: 70,
                    color: Colors.lightBlue,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'General Knowledge Quiz',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to play and save your score to Firebase.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your email.';
                      }
                      if (!value.contains('@')) {
                        return 'Enter a valid email.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your password.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    onPressed: _loading ? null : _signIn,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_loading ? 'Signing in...' : 'Sign In'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum QuizPhase {
  idle,
  loading,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  cloudVerified,
  requestError,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
}

class QuizScreen extends StatefulWidget {
  final User user;

  const QuizScreen({super.key, required this.user});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final CloudAttemptService _cloudService = CloudAttemptService();

  QuizPhase _phase = QuizPhase.idle;
  List<TriviaQuestion> _questions = [];
  List<int?> _selectedAnswers = [];
  int _currentIndex = 0;
  String? _errorMessage;
  String? _roundId;
  int _generation = 0;

  int get _answeredCount =>
      _selectedAnswers.where((answer) => answer != null).length;

  int get _correctCount {
    int count = 0;
    for (int i = 0; i < _questions.length; i++) {
      final selectedIndex = _selectedAnswers[i];
      if (selectedIndex != null &&
          _questions[i].answers[selectedIndex] == _questions[i].correctAnswer) {
        count++;
      }
    }
    return count;
  }

  bool _isCurrent(int generation) =>
      mounted &&
      generation == _generation &&
      FirebaseAuth.instance.currentUser?.uid == widget.user.uid;

  Future<void> _loadQuiz() async {
    if (_phase == QuizPhase.loading) return;
    final generation = ++_generation;

    setState(() {
      _phase = QuizPhase.loading;
      _errorMessage = null;
      _questions = [];
      _selectedAnswers = [];
      _currentIndex = 0;
      _roundId = _cloudService.createRoundId(widget.user.uid);
    });

    try {
      final questions = await TriviaService.fetchQuestions();
      if (!_isCurrent(generation)) return;

      setState(() {
        _questions = questions;
        _selectedAnswers = List<int?>.filled(questions.length, null);
        _phase = QuizPhase.playing;
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _phase = QuizPhase.requestError;
      });
    }
  }

  void _selectAnswer(int answerIndex) {
    if (_phase != QuizPhase.playing ||
        _selectedAnswers[_currentIndex] != null) {
      return;
    }
    setState(() {
      _selectedAnswers[_currentIndex] = answerIndex;
    });
  }

  void _nextQuestion() {
    if (_selectedAnswers[_currentIndex] == null) return;
    setState(() {
      if (_currentIndex < _questions.length - 1) {
        _currentIndex++;
      } else {
        _phase = QuizPhase.readyToSubmit;
      }
    });
  }

  Future<void> _submitScore() async {
    if (_phase != QuizPhase.readyToSubmit ||
        _answeredCount != 10 ||
        _roundId == null) {
      return;
    }

    final generation = _generation;
    final roundId = _roundId!;
    final score = _correctCount;

    setState(() {
      _phase = QuizPhase.submitting;
      _errorMessage = null;
    });

    final result = await _cloudService.submitAttempt(
      uid: widget.user.uid,
      roundId: roundId,
      correctCount: score,
    );

    if (!_isCurrent(generation)) return;
    _applyCloudResult(result);
  }

  Future<void> _retrySaveAndVerify() async {
    if (_roundId == null ||
        _phase == QuizPhase.submitting ||
        _phase == QuizPhase.verifying) {
      return;
    }

    final generation = _generation;
    setState(() {
      _phase = QuizPhase.verifying;
      _errorMessage = null;
    });

    final result = await _cloudService.retrySaveAndVerify(
      uid: widget.user.uid,
      roundId: _roundId!,
      correctCount: _correctCount,
    );

    if (!_isCurrent(generation)) return;
    _applyCloudResult(result);
  }

  void _applyCloudResult(CloudSaveResult result) {
    setState(() {
      _errorMessage = result.message;
      _phase = switch (result.status) {
        CloudSaveStatus.cloudVerified => QuizPhase.cloudVerified,
        CloudSaveStatus.saveUnknown => QuizPhase.saveUnknown,
        CloudSaveStatus.permissionDenied => QuizPhase.permissionDenied,
        CloudSaveStatus.verificationUnavailable =>
          QuizPhase.verificationUnavailable,
      };
    });
  }

  void _restartQuiz() {
    ++_generation;
    setState(() {
      _phase = QuizPhase.idle;
      _questions = [];
      _selectedAnswers = [];
      _currentIndex = 0;
      _errorMessage = null;
      _roundId = null;
    });
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('General Knowledge Quiz'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: switch (_phase) {
                QuizPhase.idle => _buildStart(),
                QuizPhase.loading => _buildLoading(),
                QuizPhase.playing => _buildQuestion(),
                QuizPhase.readyToSubmit => _buildResults(),
                QuizPhase.submitting => _buildBusy(
                  'Saving score to Firestore...',
                ),
                QuizPhase.verifying => _buildBusy(
                  'Checking server and recovering quiz save...',
                ),
                QuizPhase.cloudVerified => _buildCloudStatus(),
                QuizPhase.requestError => _buildRequestError(),
                QuizPhase.saveUnknown ||
                QuizPhase.permissionDenied ||
                QuizPhase.verificationUnavailable => _buildCloudStatus(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStart() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.psychology_outlined,
          size: 75,
          color: Colors.lightBlue,
        ),
        const SizedBox(height: 20),
        const Text(
          'Ready for the Quiz?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          '10 easy General Knowledge questions.\n'
          'Each question has four possible answers.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _loadQuiz,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Quiz'),
        ),
        const SizedBox(height: 16),
        Text(
          'Signed in as ${widget.user.email ?? "Unknown"}',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return _buildBusy('Loading questions from Open Trivia Database...');
  }

  Widget _buildBusy(String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildRequestError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 65, color: Colors.red),
        const SizedBox(height: 16),
        const Text(
          'Could not load the quiz',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          _errorMessage ?? 'Unknown request error.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _loadQuiz, child: const Text('Try Again')),
      ],
    );
  }

  Widget _buildQuestion() {
    final question = _questions[_currentIndex];
    final selectedIndex = _selectedAnswers[_currentIndex];
    final answered = selectedIndex != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Question ${_currentIndex + 1} of ${_questions.length}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
          ),
          const SizedBox(height: 24),
          Text(
            question.question,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          for (int index = 0; index < question.answers.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: answered ? null : () => _selectAnswer(index),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.centerLeft,
                  backgroundColor:
                      answered &&
                          question.answers[index] == question.correctAnswer
                      ? Colors.green.shade100
                      : answered && index == selectedIndex
                      ? Colors.red.shade100
                      : null,
                ),
                child: Text(
                  question.answers[index],
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          if (answered) ...[
            const SizedBox(height: 12),
            Text(
              question.answers[selectedIndex] == question.correctAnswer
                  ? 'Correct! +1 point'
                  : 'Incorrect. Correct answer: ${question.correctAnswer}',
              style: TextStyle(
                color: question.answers[selectedIndex] == question.correctAnswer
                    ? Colors.green.shade800
                    : Colors.red.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _nextQuestion,
              child: Text(
                _currentIndex == _questions.length - 1
                    ? 'View Results'
                    : 'Next Question',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            size: 65,
            color: Colors.amber,
          ),
          const SizedBox(height: 12),
          const Text(
            'Quiz Completed!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Your Score: $_correctCount / ${_questions.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Answered: $_answeredCount / ${_questions.length}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Review Your Answers',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _questions.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${_questions[i].question}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your answer: '
                      '${_questions[i].answers[_selectedAnswers[i]!]}',
                    ),
                    Text('Correct answer: ${_questions[i].correctAnswer}'),
                    const SizedBox(height: 5),
                    Text(
                      _questions[i].answers[_selectedAnswers[i]!] ==
                              _questions[i].correctAnswer
                          ? 'Correct'
                          : 'Incorrect',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            _questions[i].answers[_selectedAnswers[i]!] ==
                                _questions[i].correctAnswer
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitScore,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Submit Score to Cloud'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _restartQuiz,
            child: const Text('Discard and Play Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudStatus() {
    final verified = _phase == QuizPhase.cloudVerified;
    final denied = _phase == QuizPhase.permissionDenied;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            verified
                ? Icons.cloud_done_outlined
                : denied
                ? Icons.lock_outline
                : Icons.cloud_off_outlined,
            size: 75,
            color: verified
                ? Colors.green
                : denied
                ? Colors.red
                : Colors.orange,
          ),
          const SizedBox(height: 18),
          Text(
            verified
                ? 'Cloud Verified!'
                : denied
                ? 'Permission Denied'
                : _phase == QuizPhase.saveUnknown
                ? 'Save Status Unknown'
                : 'Verification Unavailable',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Text(_errorMessage ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Text(
            'Score: $_correctCount / 10',
            style: const TextStyle(fontSize: 21),
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Round ID: ${_roundId ?? "Unavailable"}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!verified)
            FilledButton.icon(
              onPressed: _retrySaveAndVerify,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('Retry Save & Verify'),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _restartQuiz,
            child: Text(verified ? 'Play Again' : 'Start a New Quiz'),
          ),
          if (!verified) ...[
            const SizedBox(height: 12),
            const Text(
              'Do not assume your score was saved. '
              'Verify the existing round before starting a new one.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
