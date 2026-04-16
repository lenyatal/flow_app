import 'package:http/http.dart' as http;

class SoundCloudService {
  String? _clientId;

  // Твоя идея: автоматический поиск Client ID
  Future<String?> fetchClientId() async {
    try {
      // 1. Заходим на главную
      final response = await http.get(Uri.parse('https://soundcloud.com'));
      if (response.statusCode != 200) return null;

      // 2. Ищем регуляркой ссылки на JS скрипты (они в конце страницы)
      final jsUrls =
          RegExp(r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"')
              .allMatches(response.body)
              .map((m) => m.group(1))
              .toList();

      // 3. Перебираем скрипты, пока не найдем тот, где лежит клиент айди
      for (var url in jsUrls.reversed) {
        // Обычно он в последних файлах
        final jsResponse = await http.get(Uri.parse(url!));
        final match = RegExp(r'client_id:"([a-zA-Z0-9]{32})"')
            .firstMatch(jsResponse.body);

        if (match != null) {
          _clientId = match.group(1);
          print("FOUND CLIENT ID: $_clientId");
          return _clientId;
        }
      }
    } catch (e) {
      print("Error fetching Client ID: $e");
    }
    return null;
  }

  // Поиск треков (теперь мы можем это делать!)
  Future<List<dynamic>> searchTracks(String query) async {
    if (_clientId == null) await fetchClientId();

    final url =
        'https://api-v2.soundcloud.com/search/tracks?q=$query&client_id=$_clientId&limit=20';
    final response = await http.get(Uri.parse(url));

    // Тут потом добавим обработку JSON
    print("Search status: ${response.statusCode}");
    return [];
  }
}
