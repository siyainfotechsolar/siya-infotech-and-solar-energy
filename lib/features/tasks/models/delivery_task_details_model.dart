class DeliveryTaskDetailsModel {
  final String taskId;
  final String customerId;
  final String customerName;
  final String customerMobile;
  final String deliveryAddress;
  final String? village;
  final String? applicationId;
  final String taskName;
  final String? taskDescription;
  final String? dueDate;
  final String? deliveredAt;
  final String priority;
  final String status;
  final String? completionRemark;
  final List<Map<String, dynamic>> materials;
  final List<Map<String, dynamic>> photos;
  final List<Map<String, dynamic>> assignedStaff;

  DeliveryTaskDetailsModel({
    required this.taskId,
    required this.customerId,
    required this.customerName,
    required this.customerMobile,
    required this.deliveryAddress,
    this.village,
    this.applicationId,
    required this.taskName,
    this.taskDescription,
    this.dueDate,
    this.deliveredAt,
    required this.priority,
    required this.status,
    this.completionRemark,
    required this.materials,
    required this.photos,
    required this.assignedStaff,
  });

  factory DeliveryTaskDetailsModel.fromJson(Map<String, dynamic> json) {
    return DeliveryTaskDetailsModel(
      taskId: json['task_id'] ?? json['id'] ?? '',
      customerId: json['customer_id'] ?? '',
      customerName: json['customer_name'] ?? (json['customers'] != null ? json['customers']['name'] : 'N/A'),
      customerMobile: json['customer_mobile'] ?? (json['customers'] != null ? json['customers']['mobile'] : 'N/A'),
      deliveryAddress: json['delivery_address'] ?? (json['customers'] != null ? (json['customers']['address'] ?? json['customers']['village'] ?? 'N/A') : 'N/A'),
      village: json['village'] ?? (json['customers'] != null ? json['customers']['village'] : null),
      applicationId: json['pm_surya_ghar_application_id'] ?? (json['customers'] != null ? json['customers']['consumer_number'] : null),
      taskName: json['name'] ?? 'Delivery Task',
      taskDescription: json['description'],
      dueDate: json['due_date'],
      deliveredAt: json['delivered_at'] ?? json['completed_at'],
      priority: json['priority'] ?? 'normal',
      status: json['status'] ?? 'pending',
      completionRemark: json['completion_remark'],
      materials: (json['materials'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      photos: (json['delivery_photos'] ?? json['photos'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      assignedStaff: (json['assigned_staff'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    );
  }
}
