class ConversationTurn {
  final String role; // 'user' or 'model'
  final List<Map<String, dynamic>> parts;

  ConversationTurn({
    required this.role,
    required this.parts,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'parts': parts,
      };

  factory ConversationTurn.textUser(String text) {
    return ConversationTurn(
      role: 'user',
      parts: [
        {'text': text}
      ],
    );
  }

  factory ConversationTurn.imageUser({
    required String textPrompt,
    required String base64Image,
    String mimeType = 'image/jpeg',
  }) {
    return ConversationTurn(
      role: 'user',
      parts: [
        {'text': textPrompt},
        {
          'inline_data': {
            'mime_type': mimeType,
            'data': base64Image,
          }
        }
      ],
    );
  }

  factory ConversationTurn.modelText(String text) {
    return ConversationTurn(
      role: 'model',
      parts: [
        {'text': text}
      ],
    );
  }
}
