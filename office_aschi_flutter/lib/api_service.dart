import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiService {
  final String baseUrl;

  ApiService({this.baseUrl = 'https://officeaschi.azurewebsites.net/api'});

  Map<String, String> _jsonHeaders() => {
    'Content-Type': 'application/json; charset=UTF-8',
  };
  Map<String, String> _totpHeaders(
    String entityType,
    int entityId,
    String code,
  ) => {..._jsonHeaders(), 'Authorization': 'TOTP $entityType:$entityId:$code'};

  // --- Teams ---
  Future<List<TeamSearchResult>> searchTeams([String? query]) async {
    var url = '$baseUrl/teams';
    if (query != null && query.isNotEmpty)
      url += '?q=${Uri.encodeQueryComponent(query)}';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((j) => TeamSearchResult.fromJson(j))
          .toList();
    }
    throw Exception('Failed to load teams');
  }

  Future<TeamResponse> getTeam(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/teams/$id'));
    if (response.statusCode == 200)
      return TeamResponse.fromJson(json.decode(response.body));
    throw Exception('Team not found');
  }

  Future<TeamResponse> createTeam(
    String? name,
    String secretKey,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teams'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'secretKey': secretKey,
        'totpCode': totpCode,
      }),
    );
    if (response.statusCode == 201)
      return TeamResponse.fromJson(json.decode(response.body));
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to create team');
  }

  Future<void> deleteTeam(int id, String totpCode) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$id'),
      headers: _totpHeaders('manager', id, totpCode),
    );
    if (response.statusCode != 200) throw Exception('Failed to delete team');
  }

  // --- Seats ---
  Future<List<SeatResponse>> listSeats(int teamId) async {
    final response = await http.get(Uri.parse('$baseUrl/teams/$teamId/seats'));
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((j) => SeatResponse.fromJson(j))
          .toList();
    }
    throw Exception('Failed to load seats');
  }

  Future<SeatResponse> addSeat(
    int teamId,
    String label,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teams/$teamId/seats'),
      headers: _totpHeaders('manager', teamId, totpCode),
      body: jsonEncode({'label': label}),
    );
    if (response.statusCode == 201)
      return SeatResponse.fromJson(json.decode(response.body));
    throw Exception('Failed to add seat');
  }

  Future<void> deleteSeat(int teamId, int seatId, String totpCode) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$teamId/seats/$seatId'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete seat');
    }
  }

  // --- Reportees ---
  Future<List<ReporteeResponse>> listReportees(int teamId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/teams/$teamId/reportees'),
    );
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((j) => ReporteeResponse.fromJson(j))
          .toList();
    }
    throw Exception('Failed to load reportees');
  }

  Future<ReporteeResponse> joinTeam(
    int teamId,
    String friendlyName,
    String secretKey,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teams/$teamId/reportees'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'friendlyName': friendlyName,
        'secretKey': secretKey,
        'totpCode': totpCode,
      }),
    );
    if (response.statusCode == 201)
      return ReporteeResponse.fromJson(json.decode(response.body));
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to join team');
  }

  Future<void> approveReportee(
    int teamId,
    int reporteeId,
    String totpCode,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/teams/$teamId/reportees/$reporteeId/approve'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) throw Exception('Failed to approve');
  }

  Future<void> denyReportee(int teamId, int reporteeId, String totpCode) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$teamId/reportees/$reporteeId/deny'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) throw Exception('Failed to deny');
  }

  Future<void> removeReportee(
    int teamId,
    int reporteeId,
    String totpCode,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$teamId/reportees/$reporteeId'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) throw Exception('Failed to remove');
  }

  // --- Bookings ---
  Future<AvailabilityResponse> getAvailability(int teamId, String date) async {
    final response = await http.get(
      Uri.parse('$baseUrl/bookings/availability/$teamId?date=$date'),
    );
    if (response.statusCode == 200)
      return AvailabilityResponse.fromJson(json.decode(response.body));
    throw Exception('Failed to load availability');
  }

  Future<BookingResponse> bookSeat(
    int reporteeId,
    int seatId,
    String date,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/bookings'),
      headers: _totpHeaders('reportee', reporteeId, totpCode),
      body: jsonEncode({
        'reporteeId': reporteeId,
        'seatId': seatId,
        'date': date,
      }),
    );
    if (response.statusCode == 201)
      return BookingResponse.fromJson(json.decode(response.body));
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to book seat');
  }

  Future<void> cancelBooking(
    int bookingId,
    int reporteeId,
    String totpCode,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/bookings/$bookingId'),
      headers: _totpHeaders('reportee', reporteeId, totpCode),
    );
    if (response.statusCode != 200) throw Exception('Failed to cancel booking');
  }

  // --- TOTP ---
  Future<bool> verifyTotp(String entityType, int entityId, String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/totp/verify'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'entityType': entityType,
        'entityId': entityId,
        'code': code,
      }),
    );
    if (response.statusCode == 200)
      return json.decode(response.body)['valid'] == true;
    return false;
  }
}
