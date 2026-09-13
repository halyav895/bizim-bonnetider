import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

void main() {
  runApp(const BonnetidApp());
}

class BonnetidApp extends StatelessWidget {
  const BonnetidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IRN Bønnetider',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF091110),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String selectedCity = 'Oslo';
  final List<String> cities = [
    'Oslo',
    'Ringerike',
    'Hønefoss',
    'Drammen',
    'Bergen',
    'Trondheim',
    'Stavanger',
    'Kristiansand'
  ];

  bool isLoading = true;
  Map<String, String> prayerTimes = {};
  String nextPrayerName = '';
  String hijriDate = '';
  String gregorianDate = '';
  Duration remainingTime = Duration.zero;
  double progressValue = 0.0;
  Timer? countdownTimer;
  List<dynamic> monthlyCalendarData = [];

  @override
  void initState() {
    super.initState();
    fetchPrayerTimes(selectedCity);
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  void _openQiblaFinder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Qibla Finder yönlendirmesi: https://qiblafinder.withgoogle.com/'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> fetchPrayerTimes(String city) async {
    setState(() {
      isLoading = true;
    });

    countdownTimer?.cancel();

    try {
      final response1 = await http.get(
        Uri.parse('https://api.aladhan.com/v1/timingsByCity?city=$city&country=Norway&method=3&school=0'),
      );

      final response2 = await http.get(
        Uri.parse('https://api.aladhan.com/v1/timingsByCity?city=$city&country=Norway&method=3&school=1'),
      );

      final now = DateTime.now();
      final calendarResponse = await http.get(
        Uri.parse('https://api.aladhan.com/v1/calendarByCity/${now.year}/${now.month}?city=$city&country=Norway&method=3'),
      );

      if (response1.statusCode == 200 && response2.statusCode == 200) {
        final data1 = jsonDecode(response1.body);
        final data2 = jsonDecode(response2.body);
        
        final timings1 = data1['data']['timings'];
        final timings2 = data2['data']['timings'];
        final dateInfo = data1['data']['date'];

        if (calendarResponse.statusCode == 200) {
          final calData = jsonDecode(calendarResponse.body);
          monthlyCalendarData = calData['data'];
        }

        setState(() {
          prayerTimes = {
            'İmsak (Fajr)': timings1['Fajr'],
            'Güneş (Izhar)': timings1['Sunrise'],
            'Öğle (Dhuhr)': timings1['Dhuhr'],
            'İkindi (Asr - Hanafi)': timings2['Asr'],
            'Akşam (Maghrib)': timings1['Maghrib'],
            'Yatsı (Isha)': timings1['Isha'],
          };
          
          gregorianDate = '${dateInfo['gregorian']['day']} ${dateInfo['gregorian']['month']['en']} ${dateInfo['gregorian']['year']}';
          hijriDate = '${dateInfo['hijri']['day']} ${dateInfo['hijri']['month']['en']} ${dateInfo['hijri']['year']} AH';

          isLoading = false;
        });

        calculateNextPrayer();
        startTimer();
      } else {
        throw Exception('Veri çekilemedi');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void calculateNextPrayer() {
    final now = DateTime.now();
    DateTime? nextTime;
    DateTime? previousTime;
    String name = '';

    List<MapEntry<String, DateTime>> entries = [];

    for (var entry in prayerTimes.entries) {
      final parts = entry.value.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      entries.add(MapEntry(entry.key, DateTime(now.year, now.month, now.day, hour, minute)));
    }

    for (int i = 0; i < entries.length; i++) {
      if (entries[i].value.isAfter(now)) {
        nextTime = entries[i].value;
        name = entries[i].key;
        previousTime = i > 0 ? entries[i - 1].value : entries.last.value.subtract(const Duration(days: 1));
        break;
      }
    }

    if (nextTime == null && entries.isNotEmpty) {
      nextTime = entries.first.value.add(const Duration(days: 1));
      name = entries.first.key;
      previousTime = entries.last.value;
    }

    if (nextTime != null && previousTime != null) {
      final totalDuration = nextTime.difference(previousTime).inSeconds;
      final elapsed = now.difference(previousTime).inSeconds;
      
      setState(() {
        nextPrayerName = name;
        remainingTime = nextTime!.difference(now);
        progressValue = (totalDuration > 0) ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.0;
      });
    }
  }

  void startTimer() {
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingTime.inSeconds > 0) {
        setState(() {
          remainingTime = remainingTime - const Duration(seconds: 1);
          calculateNextPrayer();
        });
      } else {
        calculateNextPrayer();
      }
    });
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  void _showMonthlyCalendar() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111E1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Månedlig kalender ($selectedCity)',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: monthlyCalendarData.length,
                  itemBuilder: (context, index) {
                    final dayData = monthlyCalendarData[index];
                    final date = dayData['date']['gregorian']['date'];
                    final timings = dayData['timings'];

                    return Card(
                      color: const Color(0xFF1B2E2B),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          date,
                          style: const TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          'İmsak: ${timings['Fajr']}  |  Öğle: ${timings['Dhuhr']}  |  İkindi: ${timings['Asr']}  |  Akşam: ${timings['Maghrib']}  |  Yatsı: ${timings['Isha']}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isFriday = DateTime.now().weekday == DateTime.friday;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111E1C),
        title: const Text('IRN Bønnetider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Color(0xFF10B981)),
            onPressed: _showMonthlyCalendar,
            tooltip: '1 Aylık Takvim',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2E2B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            ),
            child: DropdownButton<String>(
              value: selectedCity,
              dropdownColor: const Color(0xFF111E1C),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              underline: Container(),
              icon: const Icon(Icons.location_on, color: Color(0xFF10B981), size: 18),
              items: cities.map((String city) {
                return DropdownMenuItem<String>(
                  value: city,
                  child: Text(city),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    selectedCity = newValue;
                  });
                  fetchPrayerTimes(newValue);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111E1C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.white60, size: 14),
                            const SizedBox(width: 8),
                            Text(gregorianDate, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.nightlight_round, color: Color(0xFFF59E0B), size: 14),
                            const SizedBox(width: 8),
                            Text(hijriDate, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF047857), Color(0xFF065F46), Color(0xFF064E3B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF047857).withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (isFriday) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFF59E0B), width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Color(0xFFF59E0B), size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Cumanız mübarek olsun / Jumu\'ah Mubarak',
                                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Text(
                          'Neste bønn: $nextPrayerName',
                          style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatDuration(remainingTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 6,
                            backgroundColor: Colors.black26,
                            color: const Color(0xFF34D399),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: _openQiblaFinder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34D399),
                            foregroundColor: const Color(0xFF064E3B),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          icon: const Icon(Icons.explore, size: 18),
                          label: const Text('Qibla Finder (Google)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView.builder(
                      itemCount: prayerTimes.length,
                      itemBuilder: (context, index) {
                        String key = prayerTimes.keys.elementAt(index);
                        String val = prayerTimes.values.elementAt(index);
                        bool isNext = key == nextPrayerName;
                        bool isSun = key.contains('Güneş');

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isNext ? const Color(0xFF065F46) : const Color(0xFF111E1C),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isNext ? const Color(0xFF34D399) : Colors.white.withValues(alpha: 0.04),
                              width: isNext ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: Icon(
                              isSun ? Icons.wb_sunny : Icons.access_time_filled,
                              color: isNext
                                  ? const Color(0xFF34D399)
                                  : (isSun ? const Color(0xFFF59E0B) : Colors.white38),
                            ),
                            title: Text(
                              key,
                              style: TextStyle(
                                color: isNext ? const Color(0xFF34D399) : (isSun ? Colors.white60 : Colors.white),
                                fontWeight: isNext ? FontWeight.bold : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                            trailing: Text(
                              val,
                              style: TextStyle(
                                color: isNext ? const Color(0xFF34D399) : Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
