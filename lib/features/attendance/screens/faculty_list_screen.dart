import 'package:flutter/material.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/bottom_sheets.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/dropdown.dart';
import '../../../core/widgets/filter_panel.dart';
import '../../../core/widgets/search_bar.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/table.dart';
import '../../../core/api_service.dart';
import '../../../core/widgets/premises_loader.dart';
import '../../../core/widgets/skeleton_loader.dart';

class FacultyListScreen extends StatefulWidget {
  final String? filterStatus;

  const FacultyListScreen({
    super.key,
    this.filterStatus,
  });

  @override
  State<FacultyListScreen> createState() => _FacultyListScreenState();
}

class _FacultyListScreenState extends State<FacultyListScreen> {
  final _searchController = TextEditingController();
  bool _isFiltersExpanded = false;
  String _selectedDept = 'All';
  String _selectedStatus = 'All';
  bool _isLoading = true;
  String? _errorMessage;

  final List<String> _departments = ['All'];
  final List<String> _statuses = ['All', 'Active', 'Pending Approval', 'Inactive'];

  List<Map<String, String>> _facultyList = [];

  @override
  void initState() {
    super.initState();
    if (widget.filterStatus != null) {
      if (widget.filterStatus!.toUpperCase() == 'ACTIVE') {
        _selectedStatus = 'Active';
      }
    }
    _loadDepartments();
    _fetchFacultyRoster();
  }

  Future<void> _loadDepartments() async {
    try {
      final depts = await ApiService.fetchDepartments();
      if (mounted) {
        setState(() {
          _departments.clear();
          _departments.add('All');
          for (var dept in depts) {
            final name = dept['name'] as String?;
            if (name != null && !_departments.contains(name)) {
              _departments.add(name);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load departments: $e');
    }
  }

  Future<void> _fetchFacultyRoster() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.get('/admin/faculty-roster');
      if (res['success'] == true && res['data'] != null) {
        if (mounted) {
          setState(() {
            _facultyList = (res['data'] as List).map((item) {
              return {
                'id': item['id']?.toString() ?? '',
                'name': item['name']?.toString() ?? '',
                'email': item['email']?.toString() ?? '',
                'dept': item['dept']?.toString() ?? '',
                'status': item['status']?.toString() ?? '',
                'attendance': item['attendance']?.toString() ?? '',
                'device': item['device']?.toString() ?? '',
              };
            }).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = res['message'] ?? 'Failed to load faculty roster.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFacultyStatus(String facultyId) async {
    try {
      final res = await ApiService.post('/admin/toggle-faculty-status/$facultyId', {});
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Status updated successfully.')),
        );
        _fetchFacultyRoster();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to update status.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filteredFaculty {
    return _facultyList.where((faculty) {
      final nameMatches = faculty['name']!.toLowerCase().contains(_searchController.text.toLowerCase());
      final emailMatches = faculty['email']!.toLowerCase().contains(_searchController.text.toLowerCase());
      final searchMatches = nameMatches || emailMatches;

      final deptMatches = _selectedDept == 'All' || faculty['dept'] == _selectedDept;
      
      bool statusMatches = true;
      if (_selectedStatus == 'Active') statusMatches = faculty['status'] == 'ACTIVE';
      if (_selectedStatus == 'Pending Approval') statusMatches = faculty['status'] == 'PENDING_APPROVAL';
      if (_selectedStatus == 'Inactive') statusMatches = faculty['status'] == 'INACTIVE';

      return searchMatches && deptMatches && statusMatches;
    }).toList();
  }

  void _showFacultyProfile(Map<String, String> faculty) {
    final theme = Theme.of(context);

    AppBottomSheet.show(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
                child: Text(
                  faculty['name']!.split(' ').last[0],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(faculty['name']!, style: AppTypography.h3),
                    Text(faculty['email']!, style: AppTypography.caption),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusChip(status: faculty['status']!),
                        const SizedBox(width: 8),
                        StatusChip(status: faculty['attendance']!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Hardware & Workspace Context', style: AppTypography.h4),
          const Divider(height: 20),
          _buildDetailRow('Assigned Department', faculty['dept']!),
          _buildDetailRow('Registered Device', faculty['device']!),
          _buildDetailRow('Active Geofence Group', 'Primary Campus Boundary'),
          _buildDetailRow('Office Hour Scoring', '94% (Last 30 Days)'),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: faculty['status'] == 'ACTIVE' ? 'Deactivate Access' : 'Activate Access',
                  variant: ButtonVariant.outline,
                  onPressed: () {
                    Navigator.pop(context);
                    final id = faculty['id'];
                    if (id != null && id.isNotEmpty) {
                      _toggleFacultyStatus(id);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppButton(
                  text: 'Edit Context',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredFaculty;

    // Map rows into cells list
    final tableRows = filtered.map((item) {
      return [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(item['email']!, style: AppTypography.caption),
          ],
        ),
        Text(item['dept']!, style: AppTypography.bodyMedium),
        StatusChip(status: item['status']!),
        StatusChip(status: item['attendance']!),
      ];
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action Bar Row
        Row(
          children: [
            Expanded(
              child: AppSearchBar(
                controller: _searchController,
                hint: 'Filter by faculty name or email address...',
                onChanged: (val) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(
                _isFiltersExpanded ? Icons.filter_alt : Icons.filter_alt_outlined,
                color: _isFiltersExpanded ? theme.colorScheme.primary : Colors.grey,
              ),
              onPressed: () => setState(() => _isFiltersExpanded = !_isFiltersExpanded),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Collapsible Filters Panel
        AppFilterPanel(
          isExpanded: _isFiltersExpanded,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 500;
              final deptDropdown = AppDropdownFormField<String>(
                value: _selectedDept,
                label: 'Department',
                items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) => setState(() => _selectedDept = val!),
              );
              final statusDropdown = AppDropdownFormField<String>(
                value: _selectedStatus,
                label: 'Account Status',
                items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) => setState(() => _selectedStatus = val!),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: deptDropdown),
                    const SizedBox(width: 16),
                    Expanded(child: statusDropdown),
                  ],
                );
              } else {
                return Column(
                  children: [
                    deptDropdown,
                    const SizedBox(height: 12),
                    statusDropdown,
                  ],
                );
              }
            },
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SkeletonCardList(itemCount: 4),
                )
              : _errorMessage != null && _facultyList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 42),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(color: theme.colorScheme.error),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _fetchFacultyRoster,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? const Center(child: Text('No faculty match criteria.'))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final isMobileWidth = MediaQuery.of(context).size.width < 768;
                            final tableWidget = AppTable(
                              headers: const ['Faculty Profile', 'Department', 'Account Status', 'Presence State'],
                              rows: tableRows,
                              onRowTap: (index) => _showFacultyProfile(filtered[index]),
                            );

                            return SingleChildScrollView(
                              child: isMobileWidth
                                  ? SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(minWidth: 700),
                                        child: tableWidget,
                                      ),
                                    )
                                  : tableWidget,
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
