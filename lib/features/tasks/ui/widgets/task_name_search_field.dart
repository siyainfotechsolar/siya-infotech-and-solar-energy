import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/providers/auth_provider.dart';

class TaskNameSearchField extends ConsumerStatefulWidget {
  final ValueChanged<String?> onTaskNameSelected;

  const TaskNameSearchField({
    super.key,
    required this.onTaskNameSelected,
  });

  @override
  ConsumerState<TaskNameSearchField> createState() => _TaskNameSearchFieldState();
}

class _TaskNameSearchFieldState extends ConsumerState<TaskNameSearchField> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  
  Timer? _debounce;
  bool _isLoading = false;
  List<String> _results = [];
  String? _selectedTaskName;
  
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 200), _hideOverlay);
      }
    });
  }

  void _onSearchChanged() {
    if (_selectedTaskName != null && _searchController.text != _selectedTaskName) {
      setState(() {
        _selectedTaskName = null;
      });
      widget.onTaskNameSelected(null);
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
      });
      _overlayEntry?.markNeedsBuild();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    _overlayEntry?.markNeedsBuild();
    
    try {
      final supabase = ref.read(supabaseClientProvider);
      final res = await supabase.from('task_types').select('name').ilike('name', '%$query%').limit(10);
        
      if (mounted) {
        setState(() {
          _results = (res as List).map((e) => e['name'] as String).toList();
          _isLoading = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: MediaQuery.of(context).size.width - 32,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 60),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: _buildOverlayContent(),
              ),
            ),
          ),
        );
      }
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildOverlayContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    final query = _searchController.text.trim();
    final bool exactMatch = _results.any((name) => name.toLowerCase() == query.toLowerCase());

    return ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      children: [
        if (query.isNotEmpty && !exactMatch)
          ListTile(
            leading: const Icon(Icons.add, color: Colors.blue),
            title: Text('Create new task: "$query"', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            onTap: () {
              _selectName(query);
            },
          ),
        ..._results.map((name) => ListTile(
          title: Text(name),
          onTap: () {
            _selectName(name);
          },
        )),
      ],
    );
  }

  void _selectName(String name) {
    _searchController.text = name;
    setState(() {
      _selectedTaskName = name;
      _results = [];
    });
    widget.onTaskNameSelected(name);
    _hideOverlay();
    _focusNode.unfocus();
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideOverlay();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _searchController,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: 'Task Name *',
          hintText: 'Search or enter task name...',
          prefixIcon: const Icon(Icons.task_alt),
          suffixIcon: _selectedTaskName != null 
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        ),
        validator: (val) {
          if (val == null || val.isEmpty) return 'Required';
          if (_selectedTaskName == null) return 'Please select or create a valid task name';
          return null;
        },
      ),
    );
  }
}
