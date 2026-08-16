class WiremanTaskDetailsModel {
  final String taskId;
  final String customerId;
  final String customerName;
  final String customerMobile;
  final String address;
  final String? village;
  final String? applicationId;
  final String taskName;
  final String? taskDescription;
  final String? dueDate;
  final String priority;
  final String status;
  final String? completionRemark;
  final String? systemCapacity;
  final String? inverterSerial;
  final String? inverterPhotoUrl;
  final String? meterNumber;
  final String? generationReading;
  final String? generationPhotoUrl;
  final double? geoLat;
  final double? geoLong;
  final String? geoTimestamp;
  final int panelQuantity;
  final List<String> panelSerials;
  final Map<String, String> electricalWorkStatus;
  final String? incompleteReason;
  final String? incompleteDetails;
  final String? incompleteMarkedBy;
  final String? incompleteAt;
  final List<Map<String, dynamic>> installationTasks;
  final List<Map<String, dynamic>> electricalMaterials;
  final List<Map<String, dynamic>> photos;

  WiremanTaskDetailsModel({
    required this.taskId,
    required this.customerId,
    required this.customerName,
    required this.customerMobile,
    required this.address,
    this.village,
    this.applicationId,
    required this.taskName,
    this.taskDescription,
    this.dueDate,
    required this.priority,
    required this.status,
    this.completionRemark,
    this.systemCapacity,
    this.inverterSerial,
    this.inverterPhotoUrl,
    this.meterNumber,
    this.generationReading,
    this.generationPhotoUrl,
    this.geoLat,
    this.geoLong,
    this.geoTimestamp,
    this.panelQuantity = 6,
    required this.panelSerials,
    required this.electricalWorkStatus,
    this.incompleteReason,
    this.incompleteDetails,
    this.incompleteMarkedBy,
    this.incompleteAt,
    required this.installationTasks,
    required this.electricalMaterials,
    required this.photos,
  });

  factory WiremanTaskDetailsModel.fromJson(Map<String, dynamic> json) {
    // Parse serials
    final rawSerials = json['panel_serials'] ?? json['panel_serial_numbers'];
    List<String> serials = [];
    if (rawSerials is List) {
      serials = rawSerials.map((e) => e.toString()).toList();
    }

    // Parse electrical work statuses
    final rawWork = json['electrical_work_status'] ?? json['work_status'];
    Map<String, String> workStatus = {};
    if (rawWork is Map) {
      workStatus = rawWork.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    String? incompleteReason = json['incomplete_reason']?.toString();
    String? incompleteDetails = json['incomplete_details']?.toString();
    final remark = json['completion_remark']?.toString();

    if (incompleteReason == null && remark != null && remark.contains('NOT COMPLETED')) {
      final startIndex = remark.indexOf('NOT COMPLETED');
      final content = remark.substring(startIndex);
      if (content.contains('(') && content.contains(')')) {
        final inner = content.substring(content.indexOf('(') + 1, content.lastIndexOf(')'));
        final parts = inner.split(': ');
        incompleteReason = parts[0];
        if (parts.length > 1) {
          incompleteDetails = parts.sublist(1).join(': ');
        }
      } else {
        incompleteReason = 'Not Completed';
        incompleteDetails = remark;
      }
    }

    return WiremanTaskDetailsModel(
      taskId: json['task_id'] ?? json['id'] ?? '',
      customerId: json['customer_id'] ?? '',
      customerName: json['customer_name'] ?? (json['customers'] != null ? json['customers']['name'] : 'N/A'),
      customerMobile: json['customer_mobile'] ?? (json['customers'] != null ? json['customers']['mobile'] : 'N/A'),
      address: json['address'] ?? (json['customers'] != null ? (json['customers']['address'] ?? json['customers']['village'] ?? 'N/A') : 'N/A'),
      village: json['village'] ?? (json['customers'] != null ? json['customers']['village'] : null),
      applicationId: json['pm_surya_ghar_application_id'] ?? (json['customers'] != null ? json['customers']['consumer_number'] : null),
      taskName: json['name'] ?? 'Electrical / Wireman Task',
      taskDescription: json['description'],
      dueDate: json['due_date'],
      priority: json['priority'] ?? 'normal',
      status: json['status'] ?? 'pending',
      completionRemark: remark,
      systemCapacity: json['system_capacity']?.toString() ?? json['capacity']?.toString(),
      inverterSerial: json['inverter_serial']?.toString(),
      inverterPhotoUrl: json['inverter_photo_url']?.toString(),
      meterNumber: json['meter_number']?.toString() ?? json['meter_serial']?.toString(),
      generationReading: json['generation_reading']?.toString(),
      generationPhotoUrl: json['generation_photo_url']?.toString(),
      geoLat: (json['geo_lat'] as num?)?.toDouble() ?? (json['latitude'] as num?)?.toDouble(),
      geoLong: (json['geo_long'] as num?)?.toDouble() ?? (json['longitude'] as num?)?.toDouble(),
      geoTimestamp: json['geo_timestamp']?.toString(),
      panelQuantity: (json['panel_quantity'] as num?)?.toInt() ?? 6,
      panelSerials: serials,
      electricalWorkStatus: workStatus,
      incompleteReason: incompleteReason,
      incompleteDetails: incompleteDetails,
      incompleteMarkedBy: json['incomplete_marked_by']?.toString() ?? (json['incomplete_staff'] != null ? json['incomplete_staff']['name'] : null),
      incompleteAt: json['incomplete_at']?.toString(),
      installationTasks: (json['installation_tasks'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      electricalMaterials: (json['electrical_materials'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      photos: (json['photos'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    );
  }
}
