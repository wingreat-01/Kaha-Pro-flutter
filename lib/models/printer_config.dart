/// A saved printer. Bluetooth printers are addressed by MAC address;
/// network printers by IP + port (raw ESC/POS over TCP, port 9100 is
/// the near-universal default for thermal receipt printers — same
/// port most POS software and printer drivers assume unless the
/// printer's own settings say otherwise).
enum PrinterConnectionType { bluetooth, network }

class PrinterConfig {
  final PrinterConnectionType type;
  final String name; // display name — device name for Bluetooth, or a
                      // user-given label for a network printer
  final String address; // Bluetooth MAC address, or IP address
  final int port; // only meaningful for network; ignored for Bluetooth

  const PrinterConfig({
    required this.type,
    required this.name,
    required this.address,
    this.port = 9100,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'name': name,
        'address': address,
        'port': port,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
        type: PrinterConnectionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => PrinterConnectionType.network,
        ),
        name: json['name'] as String,
        address: json['address'] as String,
        port: (json['port'] as num?)?.toInt() ?? 9100,
      );
}
