import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'chat.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  _InboxPageState createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _bpjsData = [];
  List<Map<String, dynamic>> _verifData = [];
  bool _isLoading = true;
  int? _employeeId;
  String _selectedTab = 'Permintaan Karyawan';
  final List<String> _tabs = [
    'Permintaan Karyawan',
    'Konsultasi',
    'BPJS',
    'Verifikasi Data'
  ];
  bool _hasUnreadNotifications = false;
  List<String> _roomIds = [];
  final Map<String, Map<String, dynamic>> _roomOpponentCache = {};
  DateTime? _lastVerifFetchTime;

  @override
  void initState() {
    super.initState();
    _clearLocalData();
    _loadEmployeeId();
  }

  Future<void> _clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final roomId = prefs.getString('roomId');
    if (roomId != null) {
      await prefs.remove('messages_$roomId');
    }
  }

  Future<void> _loadEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _employeeId = prefs.getInt('idEmployee');
      _isLoading = true;
    });
    if (_employeeId != null) {
      await _fetchRooms();
      await _fetchComplaints();
      await _fetchBpjsData();
      await _fetchVerifData();
      await _fetchMessages();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Employee ID not found. Please log in again.')),
        );
      }
    }
  }

  Future<void> _fetchRooms() async {
    if (_employeeId == null || !mounted) return;
    try {
      final url = Uri.parse('http://103.31.235.237:5555/api/ChatRooms');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> rooms = [];
        if (data is List) {
          rooms = data.cast<Map<String, dynamic>>();
        }
        final myEmployeeId = _employeeId.toString();
        final myRooms = rooms.where((room) {
          final konsultasi = room['Konsultasi'];
          return konsultasi != null &&
              (konsultasi['IdEmployee']?.toString() == myEmployeeId ||
                  konsultasi['IdKaryawan']?.toString() == myEmployeeId);
        }).toList();
        setState(() {
          _roomIds = myRooms
              .map((room) => room['Id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      print('Error fetching rooms: $e');
    }
  }

  Future<void> _fetchMessages() async {
    if (_employeeId == null || _roomIds.isEmpty || !mounted) return;
    try {
      List<Map<String, dynamic>> allMessages = [];
      for (String roomId in _roomIds) {
        final url = Uri.parse(
            'http://103.31.235.237:5555/api/ChatMessages/room/$roomId?currentUserId=$_employeeId');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic> && data['Messages'] is List) {
            allMessages.addAll(data['Messages'].cast<Map<String, dynamic>>());
            if (data['Opponent'] != null) {
              _roomOpponentCache[roomId] =
                  data['Opponent'] as Map<String, dynamic>;
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _notifications = allMessages.where((msg) {
            final status = msg['Status']?.toString() ?? '';
            final senderId = msg['SenderId']?.toString() ?? '';
            final roomId = msg['RoomId']?.toString() ?? '';
            final isFromHR = senderId != _employeeId.toString();
            final isUnread = status == 'Terkirim';
            final isMyRoom = _roomIds.contains(roomId);
            return isFromHR && isUnread && isMyRoom;
          }).map((msg) {
            final roomId = msg['RoomId']?.toString() ?? '';
            final senderName = msg['Sender']?['EmployeeName']?.toString() ??
                'HR Tidak Diketahui';
            return {
              'id': msg['Id']?.toString() ?? '',
              'message': msg['Message']?.toString() ?? 'No message',
              'senderName': senderName,
              'senderId': msg['SenderId']?.toString() ?? '',
              'createdAt': msg['CreatedAt']?.toString() ?? '',
              'roomId': roomId,
              'isRead': false,
            };
          }).toList();
          _hasUnreadNotifications = _notifications.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchComplaints() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse(
          'http://103.31.235.237:5555/api/keluhans?employeeId=$_employeeId'));
      print('Fetch Complaints Status: ${response.statusCode}');
      print('Fetch Complaints Body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _complaints =
                (data as List).cast<Map<String, dynamic>>().where((complaint) {
              final isMatch =
                  complaint['IdEmployee']?.toString() == _employeeId.toString();
              print(
                  'Complaint Id=${complaint['Id']}, IdEmployee=${complaint['IdEmployee']}, MatchesEmployeeId=$isMatch');
              return isMatch;
            }).toList();
            print('Filtered Complaints: $_complaints');
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Failed to load complaints: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching complaints: $e')),
        );
      }
    }
  }

  Future<void> _fetchBpjsData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse(
          'http://103.31.235.237:5555/api/bpjs?employeeId=$_employeeId'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _bpjsData =
                (data as List).cast<Map<String, dynamic>>().where((bpjs) {
              return bpjs['IdEmployee']?.toString() == _employeeId.toString();
            }).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Failed to load BPJS data: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching BPJS data: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchVerifRequestDetails(int idSource) async {
    try {
      final response = await http.get(
        Uri.parse(
            'http://103.31.235.237:5555/api/VerifData/requests/$idSource'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _fetchVerifData({bool forceFetch = false}) async {
    if (!mounted || _employeeId == null) return;

    // Skip fetch if recent fetch was done (within 1 minute), unless forced
    if (!forceFetch &&
        _lastVerifFetchTime != null &&
        DateTime.now().difference(_lastVerifFetchTime!).inMinutes < 1) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse(
            'http://103.31.235.237:5555/api/VerifData/requests?employeeId=$_employeeId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        final filteredVerifData =
            data.cast<Map<String, dynamic>>().where((verif) {
          final matches =
              verif['EmployeeId']?.toString() == _employeeId.toString();
          final validStatus =
              verif['Status'] == 'Diajukan' || verif['Status'] == 'Approved';
          return matches && validStatus;
        }).map((verif) {
          return {
            'Id': verif['Id'],
            'Status': verif['Status'] == 'Diajukan' ? 'Diajukan' : 'Disetujui',
            'Source': 'VerifData',
            'FieldName': verif['FieldName']?.toString() ?? 'N/A',
            'OldValue': verif['OldValue']?.toString() ?? 'N/A',
            'NewValue': verif['NewValue']?.toString() ?? 'N/A',
            'RequestedAt': verif['RequestedAt']?.toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _verifData = filteredVerifData;
            _isLoading = false;
            _lastVerifFetchTime = DateTime.now();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Failed to load verification data: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching verification data: $e')),
        );
      }
    }
  }

  Future<void> _updateServerStatus(String messageId, String status) async {
    try {
      final url = Uri.parse(
          'http://103.31.235.237:5555/api/ChatMessages/update-status/$messageId');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      if (response.statusCode != 200) {
        print('Failed to update server status: ${response.body}');
      }
    } catch (e) {
      print('Error updating server status: $e');
    }
  }

  Future<void> _navigateToChat(String roomId, String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('roomId', roomId);
    await _updateServerStatus(notificationId, 'Dibaca');
    if (mounted) {
      setState(() {
        _notifications.removeWhere((notif) => notif['id'] == notificationId);
        _hasUnreadNotifications = _notifications.isNotEmpty;
      });
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatPage()),
      ).then((_) async {
        await _fetchMessages();
      });
    }
  }

  String _formatTimestamp(String? timeString) {
    if (timeString == null || timeString.isEmpty) {
      return 'Unknown Date';
    }
    try {
      final formatter = DateFormat('dd MMMM yyyy HH.mm', 'id_ID');
      final dateTime = DateTime.parse(timeString).toLocal();
      return formatter.format(dateTime);
    } catch (e) {
      return timeString;
    }
  }

  Future<void> _refreshData() async {
    if (_employeeId == null) return;
    setState(() {
      _isLoading = true;
    });
    await _fetchMessages();
    await _fetchComplaints();
    await _fetchBpjsData();
    await _fetchVerifData(forceFetch: true);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double paddingValue = screenWidth < 400 ? 16.0 : 20.0;
    final double fontSizeLabel = screenWidth < 400 ? 14.0 : 16.0;
    final double imageSize = (screenWidth * 0.2).clamp(100, 150);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              "Inbox",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  color: Colors.white),
            ),
            if (_hasUnreadNotifications)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child: Text(
                  _notifications.length.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF1E88E5),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(paddingValue),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButtonFormField<String>(
                  value: _selectedTab,
                  decoration: InputDecoration(
                    labelText: 'Pilih Kategori',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    labelStyle: GoogleFonts.poppins(fontSize: fontSizeLabel),
                  ),
                  items: _tabs.map((String tab) {
                    return DropdownMenuItem<String>(
                      value: tab,
                      child: Row(
                        children: [
                          Text(
                            tab,
                            style: GoogleFonts.poppins(
                                fontSize: fontSizeLabel * 0.9,
                                fontWeight: FontWeight.w500),
                          ),
                          if (tab == 'Konsultasi' && _hasUnreadNotifications)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              child: Text(
                                _notifications.length.toString(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedTab = value;
                        if (value == 'Konsultasi') {
                          _notifications = _notifications.map((notif) {
                            return {...notif, 'isRead': true};
                          }).toList();
                          _hasUnreadNotifications = false;
                        }
                      });
                    }
                  },
                ),
              ),
            ),
            SizedBox(height: paddingValue),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _selectedTab == 'Permintaan Karyawan'
                      ? _complaints.isEmpty
                          ? Center(
                              child: Text(
                                "No complaints found. Try submitting a new complaint.",
                                style: GoogleFonts.poppins(
                                    fontSize: fontSizeLabel,
                                    color: Colors.black87),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _complaints.length,
                              itemBuilder: (context, index) {
                                final complaint = _complaints[index];
                                final tglKeluhan = complaint['TglKeluhan'] !=
                                        null
                                    ? DateTime.parse(complaint['TglKeluhan'])
                                        .toLocal()
                                        .toString()
                                        .split('.')[0]
                                    : 'Unknown Date';
                                final keluhan =
                                    complaint['Keluhan']?.toString() ??
                                        complaint['Keluhan1']?.toString() ??
                                        complaint['Message']?.toString() ??
                                        complaint['Description']?.toString() ??
                                        'No message available';
                                final urlFotoKeluhan =
                                    complaint['UrlFotoKeluhan']?.toString() ??
                                        complaint['PhotoUrl']?.toString();
                                final baseUrl = 'http://103.31.235.237:5555';
                                final imageUrl = urlFotoKeluhan != null &&
                                        urlFotoKeluhan.isNotEmpty
                                    ? (urlFotoKeluhan.startsWith('http')
                                        ? urlFotoKeluhan
                                        : '$baseUrl$urlFotoKeluhan')
                                    : null;
                                final isImage = imageUrl != null &&
                                    (imageUrl.endsWith('.jpg') ||
                                        imageUrl.endsWith('.jpeg') ||
                                        imageUrl.endsWith('.png') ||
                                        imageUrl.endsWith('.gif'));

                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Nomor Tiket: ${complaint['Id']}",
                                                style: GoogleFonts.poppins(
                                                  fontSize: fontSizeLabel,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                "Message: $keluhan",
                                                style: GoogleFonts.poppins(
                                                    fontSize: fontSizeLabel - 2,
                                                    color: Colors.black87),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                "Status: ${complaint['Status'] ?? 'Unknown'}",
                                                style: GoogleFonts.poppins(
                                                    fontSize: fontSizeLabel - 2,
                                                    color: Colors.green),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                "Date: $tglKeluhan",
                                                style: GoogleFonts.poppins(
                                                    fontSize: fontSizeLabel - 2,
                                                    color: Colors.grey),
                                              ),
                                              if (complaint['NamaFile'] !=
                                                      null &&
                                                  complaint['NamaFile']
                                                      .toString()
                                                      .isNotEmpty)
                                                Text(
                                                  "Attachment: ${complaint['NamaFile']}",
                                                  style: GoogleFonts.poppins(
                                                      fontSize:
                                                          fontSizeLabel - 2,
                                                      color: Colors.blue),
                                                ),
                                            ],
                                          ),
                                        ),
                                        isImage
                                            ? Image.network(
                                                imageUrl,
                                                width: imageSize,
                                                height: imageSize,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Container(
                                                    width: imageSize,
                                                    height: imageSize,
                                                    color: Colors.grey[200],
                                                    child: const Icon(
                                                        Icons.broken_image,
                                                        color: Colors.grey,
                                                        size: 40),
                                                  );
                                                },
                                              )
                                            : Container(
                                                width: imageSize,
                                                height: imageSize,
                                                color: Colors.grey[200],
                                                child: Center(
                                                  child: Text(
                                                    'No image',
                                                    style: GoogleFonts.poppins(
                                                        fontSize:
                                                            fontSizeLabel - 2,
                                                        color: Colors.grey),
                                                  ),
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            )
                      : _selectedTab == 'Konsultasi'
                          ? _notifications.isEmpty
                              ? Center(
                                  child: Text(
                                    "No unread consultations from HR.",
                                    style: GoogleFonts.poppins(
                                        fontSize: fontSizeLabel,
                                        color: Colors.black87),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _notifications.length,
                                  itemBuilder: (context, index) {
                                    final notif = _notifications[index];
                                    final isRead = notif['isRead'] ?? true;
                                    final timestamp =
                                        _formatTimestamp(notif['createdAt']);
                                    return GestureDetector(
                                      onTap: () {
                                        _navigateToChat(
                                            notif['roomId'], notif['id']);
                                      },
                                      child: Card(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        color: !isRead ? Colors.red[50] : null,
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Pesan dari ${notif['senderName']}",
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: fontSizeLabel,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "Message: ${notif['message']}",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color:
                                                              Colors.black87),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "Status: Belum Dibaca",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color: Colors.red),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "Date: $timestamp",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                          : _selectedTab == 'BPJS'
                              ? _bpjsData.isEmpty
                                  ? Center(
                                      child: Text(
                                        "No BPJS data found.",
                                        style: GoogleFonts.poppins(
                                            fontSize: fontSizeLabel,
                                            color: Colors.black87),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _bpjsData.length,
                                      itemBuilder: (context, index) {
                                        final bpjs = _bpjsData[index];
                                        final timestamp =
                                            bpjs['CreatedAt'] != null
                                                ? _formatTimestamp(
                                                    bpjs['CreatedAt'])
                                                : 'Unknown Date';
                                        final description =
                                            bpjs['Description']?.toString() ??
                                                'No description';
                                        final status =
                                            bpjs['Status']?.toString() ??
                                                'Unknown';

                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          elevation: 3,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "Nomor BPJS: ${bpjs['NoBpjs'] ?? 'N/A'}",
                                                  style: GoogleFonts.poppins(
                                                    fontSize: fontSizeLabel,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  "Description: $description",
                                                  style: GoogleFonts.poppins(
                                                      fontSize:
                                                          fontSizeLabel - 2,
                                                      color: Colors.black87),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  "Status: $status",
                                                  style: GoogleFonts.poppins(
                                                      fontSize:
                                                          fontSizeLabel - 2,
                                                      color: Colors.green),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  "Date: $timestamp",
                                                  style: GoogleFonts.poppins(
                                                      fontSize:
                                                          fontSizeLabel - 2,
                                                      color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    )
                              : _selectedTab == 'Verifikasi Data'
                                  ? _verifData.isEmpty
                                      ? Center(
                                          child: Text(
                                            "Tidak ada permintaan verifikasi.",
                                            style: GoogleFonts.poppins(
                                                fontSize: fontSizeLabel,
                                                color: Colors.black87),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: _verifData.length,
                                          itemBuilder: (context, index) {
                                            final verif = _verifData[index];
                                            final timestamp =
                                                verif['RequestedAt'] != null
                                                    ? _formatTimestamp(
                                                        verif['RequestedAt'])
                                                    : 'Unknown Date';
                                            final fieldName = verif['FieldName']
                                                    ?.toString() ??
                                                'N/A';
                                            final oldValue =
                                                verif['OldValue']?.toString() ??
                                                    'N/A';
                                            final newValue =
                                                verif['NewValue']?.toString() ??
                                                    'N/A';
                                            final source =
                                                verif['Source']?.toString() ??
                                                    'N/A';
                                            final displayStatus =
                                                verif['Status']?.toString() ??
                                                    'Unknown';

                                            return Card(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                              elevation: 3,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(16.0),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Permintaan Verifikasi",
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: fontSizeLabel,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: const Color(
                                                            0xFF1E88E5),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "Field: $fieldName",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color:
                                                              Colors.black87),
                                                    ),
                                                    Text(
                                                      "Dari: $oldValue",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color:
                                                              Colors.black87),
                                                    ),
                                                    Text(
                                                      "Menjadi: $newValue",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color:
                                                              Colors.black87),
                                                    ),
                                                    Text(
                                                      "Status: $displayStatus",
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize:
                                                            fontSizeLabel - 2,
                                                        color: displayStatus ==
                                                                'Diajukan'
                                                            ? Colors.orange
                                                            : Colors.green,
                                                      ),
                                                    ),
                                                    Text(
                                                      "Sumber: $source",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color:
                                                              Colors.black87),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "Tanggal: $timestamp",
                                                      style: GoogleFonts.poppins(
                                                          fontSize:
                                                              fontSizeLabel - 2,
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                  : Container(),
            ),
          ],
        ),
      ),
    );
  }
}
