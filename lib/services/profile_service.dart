import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  Future<Profile> ensureProfile(User user) async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (response != null) {
      return Profile.fromMap(response);
    }

    final senderName = _defaultSenderName(user);
    final inserted = await _client.from('profiles').insert({
      'id': user.id,
      'email': user.email,
      'sender_name': senderName,
    }).select().single();

    return Profile.fromMap(inserted);
  }

  Future<Profile> fetchProfile(String userId) async {
    final response =
        await _client.from('profiles').select().eq('id', userId).single();
    return Profile.fromMap(response);
  }

  Future<Profile> updateCheckIn(String userId, {int? timerDays}) async {
    final params = <String, dynamic>{'user_id': userId};
    if (timerDays != null) {
      params['timer_days'] = timerDays;
    }
    final response =
        await _client.rpc('update_check_in', params: params).single();
    return Profile.fromMap(response);
  }

  Future<Profile> updateTimerDays(int timerDays) async {
    final response = await _client
        .rpc('update_timer_days', params: {'p_timer_days': timerDays}).single();
    return Profile.fromMap(response);
  }

  Future<Profile> updateSenderName(String userId, String senderName) async {
    final response = await _client
        .rpc('update_sender_name', params: {'new_sender_name': senderName})
        .single();
    return Profile.fromMap(response);
  }

  String _defaultSenderName(User user) {
    final metadata = user.userMetadata ?? <String, dynamic>{};
    final possibleName = (metadata['full_name'] ?? metadata['name']) as String?;
    if (possibleName != null && possibleName.trim().isNotEmpty) {
      return possibleName.trim();
    }
    final email = user.email ?? '';
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'Afterword';
  }
}
