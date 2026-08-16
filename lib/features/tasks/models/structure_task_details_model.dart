class StructureTaskDetailsModel {
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
  final List<Map<String, dynamic>> installationTasks;
  final List<Map<String, dynamic>> photos;

  StructureTaskDetailsModel({
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
    required this.installationTasks,
    required this.photos,
  });

  factory StructureTaskDetailsModel.fromJson(Map<String, dynamic> json) {
    return StructureTaskDetailsModel(
      taskId: json['task_id'] ?? json['id'] ?? '',
      customerId: json['customer_id'] ?? '',
      customerName: json['customer_name'] ?? (json['customers'] != null ? json['customers']['name'] : 'N/A'),
      customerMobile: json['customer_mobile'] ?? (json['customers'] != null ? json['customers']['mobile'] : 'N/A'),
      address: json['address'] ?? (json['customers'] != null ? (json['customers']['address'] ?? json['customers']['village'] ?? 'N/A') : 'N/A'),
      village: json['village'] ?? (json['customers'] != null ? json['customers']['village'] : null),
      applicationId: json['pm_surya_ghar_application_id'] ?? (json['customers'] != null ? json['customers']['consumer_number'] : null),
      taskName: json['name'] ?? 'Structure Task',
      taskDescription: json['description'],
      dueDate: json['due_date'],
      priority: json['priority'] ?? 'normal',
      status: json['status'] ?? 'pending',
      completionRemark: json['completion_remark'],
      installationTasks: (json['installation_tasks'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      photos: (json['photos'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    );
  }
}
