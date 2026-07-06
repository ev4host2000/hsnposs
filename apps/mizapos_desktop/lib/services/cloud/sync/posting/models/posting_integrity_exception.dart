/// Raised when post integrity checks fail — triggers full SQLite rollback.
class PostingIntegrityException implements Exception {
  const PostingIntegrityException(this.message, {this.code = 'posting_integrity_violation'});

  final String message;
  final String code;

  @override
  String toString() => 'PostingIntegrityException($code): $message';
}
