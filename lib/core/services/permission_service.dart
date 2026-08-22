import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Categories of staff members in the CRM
enum StaffCategory {
  admin,
  supervisor,
  structureInstaller,
  wireman,
  deliveryStaff,
  otherStaff;

  /// The human-readable display string (also stored in DB `category` column)
  String get displayName {
    switch (this) {
      case StaffCategory.admin:             return 'Admin';
      case StaffCategory.supervisor:        return 'Supervisor';
      case StaffCategory.structureInstaller:return 'Structure Installer';
      case StaffCategory.wireman:           return 'Wireman / Electrical Installer';
      case StaffCategory.deliveryStaff:     return 'Delivery Staff';
      case StaffCategory.otherStaff:        return 'Other Staff';
    }
  }

  static const List<StaffCategory> all = StaffCategory.values;

  static StaffCategory fromRole(String? role, [String? categoryStr]) {
    // Try category string first
    if (categoryStr != null && categoryStr.isNotEmpty) {
      return fromString(categoryStr);
    }
    switch (role) {
      case 'admin':          return StaffCategory.admin;
      case 'supervisor':     return StaffCategory.supervisor;
      case 'installer':      return StaffCategory.structureInstaller;
      case 'wireman':        return StaffCategory.wireman;
      case 'delivery_staff': return StaffCategory.deliveryStaff;
      default:               return StaffCategory.otherStaff;
    }
  }

  static StaffCategory fromString(String? val) {
    for (final c in StaffCategory.values) {
      if (c.displayName == val) return c;
    }
    return StaffCategory.otherStaff;
  }
}


/// Data Access Scopes
enum DataAccessLevel {
  allData,      // Full data access across entire business
  teamData,     // Access team or operational business data
  assignedData, // Access only data assigned to this staff member
  limitedData,  // Highly restricted access
  noAccess,     // No data access
}

extension DataAccessLevelExtension on DataAccessLevel {
  String toDbString() {
    switch (this) {
      case DataAccessLevel.allData: return 'ALL_DATA';
      case DataAccessLevel.teamData: return 'TEAM_DATA';
      case DataAccessLevel.assignedData: return 'ASSIGNED_DATA';
      case DataAccessLevel.limitedData: return 'LIMITED_DATA';
      case DataAccessLevel.noAccess: return 'NO_ACCESS';
    }
  }

  static DataAccessLevel fromDbString(String? val) {
    switch (val) {
      case 'ALL_DATA': return DataAccessLevel.allData;
      case 'TEAM_DATA': return DataAccessLevel.teamData;
      case 'ASSIGNED_DATA': return DataAccessLevel.assignedData;
      case 'LIMITED_DATA': return DataAccessLevel.limitedData;
      case 'NO_ACCESS': return DataAccessLevel.noAccess;
      default: return DataAccessLevel.assignedData;
    }
  }

  String get displayName {
    switch (this) {
      case DataAccessLevel.allData: return 'ALL DATA';
      case DataAccessLevel.teamData: return 'TEAM / OPERATIONAL';
      case DataAccessLevel.assignedData: return 'ASSIGNED ONLY';
      case DataAccessLevel.limitedData: return 'LIMITED ACCESS';
      case DataAccessLevel.noAccess: return 'NO ACCESS';
    }
  }
}

/// Application Modules
class AppModule {
  static const String dashboard = 'dashboard';
  static const String leads = 'leads';
  static const String customers = 'customers';
  static const String tasks = 'tasks';
  static const String installation = 'installation';
  static const String materials = 'materials';
  static const String materialDispatch = 'material_dispatch';
  static const String delivery = 'delivery';
  static const String staff = 'staff';
  static const String notifications = 'notifications';
  static const String import = 'import';
  static const String export = 'export';
  static const String reports = 'reports';
  static const String settings = 'settings';
  static const String appUpdate = 'app_update';

  static const List<String> all = [
    dashboard,
    leads,
    customers,
    tasks,
    installation,
    materials,
    materialDispatch,
    delivery,
    staff,
    notifications,
    import,
    export,
    reports,
    settings,
    appUpdate,
  ];

  static String getLabel(String module) {
    switch (module) {
      case dashboard: return 'Dashboard';
      case leads: return 'Leads';
      case customers: return 'Customers';
      case tasks: return 'Tasks';
      case installation: return 'Installation';
      case materials: return 'Materials';
      case materialDispatch: return 'Material Dispatch';
      case delivery: return 'Delivery';
      case staff: return 'Staff Management';
      case notifications: return 'Notifications';
      case import: return 'Import';
      case export: return 'Export';
      case reports: return 'Reports';
      case settings: return 'Settings';
      case appUpdate: return 'App Updates';
      default: return module;
    }
  }
}

/// Actions available for modules
class PermissionAction {
  static const String view = 'view';
  static const String create = 'create';
  static const String edit = 'edit';
  static const String delete = 'delete';
  static const String assign = 'assign';
  static const String upload = 'upload';
  static const String export = 'export';
  static const String manage = 'manage';

  static const List<String> all = [
    view,
    create,
    edit,
    delete,
    assign,
    upload,
    export,
    manage,
  ];
}

/// Single Module Permission State
class ModulePermissionState {
  final bool enabled;
  final Map<String, bool> actions;

  const ModulePermissionState({
    required this.enabled,
    required this.actions,
  });

  bool can(String action) {
    if (!enabled) return false;
    if (action == PermissionAction.view) return true; // Enabled implies view
    return actions[action] ?? false;
  }

  factory ModulePermissionState.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] as bool? ?? false;
    final actionsRaw = json['actions'] as Map<String, dynamic>? ?? {};
    final actions = actionsRaw.map((key, value) => MapEntry(key, value == true));
    return ModulePermissionState(enabled: enabled, actions: actions);
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'actions': actions,
    };
  }

  ModulePermissionState copyWith({
    bool? enabled,
    Map<String, bool>? actions,
  }) {
    return ModulePermissionState(
      enabled: enabled ?? this.enabled,
      actions: actions ?? Map<String, bool>.from(this.actions),
    );
  }

  static ModulePermissionState full() {
    return ModulePermissionState(
      enabled: true,
      actions: {
        PermissionAction.view: true,
        PermissionAction.create: true,
        PermissionAction.edit: true,
        PermissionAction.delete: true,
        PermissionAction.assign: true,
        PermissionAction.upload: true,
        PermissionAction.export: true,
        PermissionAction.manage: true,
      },
    );
  }

  static ModulePermissionState disabled() {
    return ModulePermissionState(
      enabled: false,
      actions: {
        PermissionAction.view: false,
        PermissionAction.create: false,
        PermissionAction.edit: false,
        PermissionAction.delete: false,
        PermissionAction.assign: false,
        PermissionAction.upload: false,
        PermissionAction.export: false,
        PermissionAction.manage: false,
      },
    );
  }
}

/// Complete Staff Permissions Object
class StaffPermissions {
  final String staffId;
  final StaffCategory category;
  final DataAccessLevel dataAccessLevel;
  final Map<String, ModulePermissionState> modules;

  StaffPermissions({
    required this.staffId,
    required this.category,
    required this.dataAccessLevel,
    required this.modules,
  });

  bool isFieldStaff() {
    return category == StaffCategory.deliveryStaff ||
        category == StaffCategory.structureInstaller ||
        category == StaffCategory.wireman;
  }

  bool can(String module, String action) {
    if (category == StaffCategory.admin) return true;
    // FIELD STAFF RULE: Delivery Staff, Structure Installer, and Wireman NEVER have Customer Module access!
    if (isFieldStaff() && module == AppModule.customers) return false;
    final mod = modules[module];
    if (mod == null) return false;
    return mod.can(action);
  }

  bool canView(String module) => can(module, PermissionAction.view);
  bool canCreate(String module) => can(module, PermissionAction.create);
  bool canEdit(String module) => can(module, PermissionAction.edit);
  bool canDelete(String module) => can(module, PermissionAction.delete);
  bool canAssign(String module) => can(module, PermissionAction.assign);
  bool canUpload(String module) => can(module, PermissionAction.upload);
  bool canExport(String module) => can(module, PermissionAction.export);
  bool canManage(String module) => can(module, PermissionAction.manage);

  /// Field-Level Permission Check
  bool canViewField(String fieldName) {
    if (category == StaffCategory.admin) return true;
    
    // Restricted sensitive fields for normal staff
    const sensitiveFields = [
      'loan_amount',
      'purchase_cost',
      'cost_price',
      'company_margin',
      'profit',
      'commission',
      'admin_notes',
      'internal_financial_remarks',
      'salary',
      'payroll',
    ];

    if (sensitiveFields.contains(fieldName)) {
      if (category == StaffCategory.supervisor) {
        return fieldName == 'loan_amount' || fieldName == 'admin_notes';
      }
      return false;
    }
    return true;
  }

  /// Specific helper: Wireman is explicitly allowed structure/panel photo uploads
  bool isAllowedPhotoUpload(String photoType) {
    if (category == StaffCategory.admin || category == StaffCategory.supervisor) return true;
    if (category == StaffCategory.structureInstaller) return true;
    if (category == StaffCategory.wireman) {
      // Wireman can upload electrical AND structure/panel photos!
      return true;
    }
    if (category == StaffCategory.deliveryStaff) {
      return photoType == 'delivery' || photoType == 'delivery_proof';
    }
    return canUpload(AppModule.installation) || canUpload(AppModule.tasks);
  }

  factory StaffPermissions.fromJson(Map<String, dynamic> json, String staffId) {
    final cat = StaffCategory.fromString(json['category'] as String?);
    final level = DataAccessLevelExtension.fromDbString(json['data_access_level'] as String?);
    final rawModules = json['permissions'] as Map<String, dynamic>? ?? {};
    
    final map = <String, ModulePermissionState>{};
    for (final m in AppModule.all) {
      if (rawModules.containsKey(m) && rawModules[m] is Map) {
        map[m] = ModulePermissionState.fromJson(Map<String, dynamic>.from(rawModules[m]));
      } else {
        map[m] = ModulePermissionState.disabled();
      }
    }

    return StaffPermissions(
      staffId: staffId,
      category: cat,
      dataAccessLevel: level,
      modules: map,
    );
  }

  Map<String, dynamic> toJson() {
    final rawMods = <String, dynamic>{};
    modules.forEach((key, val) {
      rawMods[key] = val.toJson();
    });
    return {
      'staff_id': staffId,
      'category': category.displayName,
      'data_access_level': dataAccessLevel.toDbString(),
      'permissions': rawMods,
    };
  }

  StaffPermissions copyWith({
    StaffCategory? category,
    DataAccessLevel? dataAccessLevel,
    Map<String, ModulePermissionState>? modules,
  }) {
    return StaffPermissions(
      staffId: staffId,
      category: category ?? this.category,
      dataAccessLevel: dataAccessLevel ?? this.dataAccessLevel,
      modules: modules ?? Map<String, ModulePermissionState>.from(this.modules),
    );
  }

  /// Default permission templates per category
  static StaffPermissions getDefault(String staffId, StaffCategory category) {
    final modules = <String, ModulePermissionState>{};
    DataAccessLevel level = DataAccessLevel.assignedData;

    switch (category) {
      case StaffCategory.admin:
        level = DataAccessLevel.allData;
        for (final m in AppModule.all) {
          modules[m] = ModulePermissionState.full();
        }
        break;

      case StaffCategory.supervisor:
        level = DataAccessLevel.teamData;
        for (final m in AppModule.all) {
          if (m == AppModule.dashboard ||
              m == AppModule.leads ||
              m == AppModule.customers ||
              m == AppModule.tasks ||
              m == AppModule.installation ||
              m == AppModule.materials ||
              m == AppModule.materialDispatch ||
              m == AppModule.delivery ||
              m == AppModule.notifications ||
              m == AppModule.reports) {
            modules[m] = ModulePermissionState(
              enabled: true,
              actions: {
                PermissionAction.view: true,
                PermissionAction.create: true,
                PermissionAction.edit: true,
                PermissionAction.delete: false,
                PermissionAction.assign: true,
                PermissionAction.upload: true,
                PermissionAction.export: false,
                PermissionAction.manage: false,
              },
            );
          } else if (m == AppModule.staff) {
            // Supervisor gets operational staff view only
            modules[m] = ModulePermissionState(
              enabled: true,
              actions: {
                PermissionAction.view: true,
                PermissionAction.create: false,
                PermissionAction.edit: false,
                PermissionAction.delete: false,
                PermissionAction.assign: false,
                PermissionAction.upload: false,
                PermissionAction.export: false,
                PermissionAction.manage: false,
              },
            );
          } else if (m == AppModule.settings) {
            modules[m] = ModulePermissionState(
              enabled: true,
              actions: {
                PermissionAction.view: true,
                PermissionAction.create: false,
                PermissionAction.edit: true,
                PermissionAction.delete: false,
                PermissionAction.assign: false,
                PermissionAction.upload: false,
                PermissionAction.export: false,
                PermissionAction.manage: false,
              },
            );
          } else {
            modules[m] = ModulePermissionState.disabled();
          }
        }
        break;

      case StaffCategory.structureInstaller:
        level = DataAccessLevel.assignedData;
        for (final m in AppModule.all) {
          if (m == AppModule.dashboard || m == AppModule.notifications) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else if (m == AppModule.materials) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else if (m == AppModule.tasks || m == AppModule.installation) {
            modules[m] = ModulePermissionState(
              enabled: true,
              actions: {
                PermissionAction.view: true,
                PermissionAction.create: false,
                PermissionAction.edit: true,
                PermissionAction.delete: false,
                PermissionAction.assign: false,
                PermissionAction.upload: true,
                PermissionAction.export: false,
                PermissionAction.manage: false,
              },
            );
          } else if (m == AppModule.settings) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else {
            modules[m] = ModulePermissionState.disabled();
          }
        }
        break;

      case StaffCategory.wireman:
        level = DataAccessLevel.assignedData;
        for (final m in AppModule.all) {
          if (m == AppModule.dashboard || m == AppModule.notifications) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else if (m == AppModule.materials) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else if (m == AppModule.tasks || m == AppModule.installation) {
            modules[m] = ModulePermissionState(
              enabled: true,
              actions: {
                PermissionAction.view: true,
                PermissionAction.create: false,
                PermissionAction.edit: true,
                PermissionAction.delete: false,
                PermissionAction.assign: false,
                PermissionAction.upload: true,
                PermissionAction.export: false,
                PermissionAction.manage: false,
              },
            );
          } else if (m == AppModule.settings) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else {
            modules[m] = ModulePermissionState.disabled();
          }
        }
        break;

      case StaffCategory.deliveryStaff:
        level = DataAccessLevel.assignedData;
        for (final m in AppModule.all) {
          if (m == AppModule.dashboard || m == AppModule.notifications) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else if (m == AppModule.materials) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else if (m == AppModule.tasks || m == AppModule.delivery || m == AppModule.materialDispatch) {
            modules[m] = ModulePermissionState(
              enabled: true,
              actions: {
                PermissionAction.view: true,
                PermissionAction.create: false,
                PermissionAction.edit: true,
                PermissionAction.delete: false,
                PermissionAction.assign: false,
                PermissionAction.upload: true,
                PermissionAction.export: false,
                PermissionAction.manage: false,
              },
            );
          } else if (m == AppModule.settings) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else {
            modules[m] = ModulePermissionState.disabled();
          }
        }
        break;

      default:
        level = DataAccessLevel.assignedData;
        for (final m in AppModule.all) {
          if (m == AppModule.dashboard || m == AppModule.notifications || m == AppModule.settings) {
            modules[m] = ModulePermissionState(enabled: true, actions: {PermissionAction.view: true});
          } else {
            modules[m] = ModulePermissionState.disabled();
          }
        }
        break;
    }

    return StaffPermissions(
      staffId: staffId,
      category: category,
      dataAccessLevel: level,
      modules: modules,
    );
  }
}

/// Service to fetch and manage permissions in Flutter
class PermissionService {
  final SupabaseClient _supabase;

  PermissionService(this._supabase);

  Future<StaffPermissions> fetchUserPermissions(String userId) async {
    try {
      final staffRes = await _supabase
          .from('staff')
          .select('role, category, status')
          .eq('id', userId)
          .maybeSingle();

      if (staffRes == null || staffRes['status'] != 'active') {
        return StaffPermissions.getDefault(userId, StaffCategory.otherStaff)
            .copyWith(dataAccessLevel: DataAccessLevel.noAccess);
      }

      final category = StaffCategory.fromRole(
        staffRes['role'] as String?,
        staffRes['category'] as String?,
      );

      final permRes = await _supabase
          .from('staff_permissions')
          .select('*')
          .eq('staff_id', userId)
          .maybeSingle();

      if (permRes != null) {
        return StaffPermissions.fromJson(permRes, userId);
      } else {
        // Return category defaults
        return StaffPermissions.getDefault(userId, category);
      }
    } catch (e) {
      debugPrint('[PermissionService] Error fetching permissions: $e');
      return StaffPermissions.getDefault(userId, StaffCategory.otherStaff);
    }
  }

  Future<void> saveStaffPermissions(StaffPermissions permissions, String adminUserId) async {
    final payload = permissions.toJson();
    payload['updated_by'] = adminUserId;
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('staff_permissions')
        .upsert(payload, onConflict: 'staff_id');

    // Also update category in staff table if changed
    await _supabase
        .from('staff')
        .update({'category': permissions.category.displayName})
        .eq('id', permissions.staffId);
  }
}

final permissionServiceProvider = Provider<PermissionService>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return PermissionService(supabase);
});

final currentUserPermissionsProvider = FutureProvider<StaffPermissions>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return StaffPermissions.getDefault('', StaffCategory.otherStaff)
        .copyWith(dataAccessLevel: DataAccessLevel.noAccess);
  }
  final service = ref.watch(permissionServiceProvider);
  return await service.fetchUserPermissions(user.id);
});
