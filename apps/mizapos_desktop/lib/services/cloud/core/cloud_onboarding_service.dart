import 'package:mizapos_desktop/services/cloud/auth/auth_exception.dart';

import 'package:mizapos_desktop/services/cloud/auth/auth_manager.dart';

import 'package:mizapos_desktop/services/cloud/auth/requests/login_request.dart';

import 'package:mizapos_desktop/services/cloud/core/cloud_company_selection.dart';

import 'package:mizapos_desktop/services/cloud/core/cloud_runtime.dart';

import 'package:mizapos_desktop/services/cloud/devices/cloud_device_local_store.dart';

import 'package:mizapos_desktop/services/cloud/devices/device_exception.dart';

import 'package:mizapos_desktop/services/cloud/devices/device_manager.dart';

import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';

import 'package:mizapos_desktop/services/device_binding.dart';

import 'package:package_info_plus/package_info_plus.dart';



/// تدفق ربط الحساب السحابي بالجهاز — login ثم register عند الحاجة.

class CloudOnboardingService {

  CloudOnboardingService({

    AuthManager? authManager,

    DeviceManager? deviceManager,

    CloudRuntime? runtime,

  })  : _auth = authManager ?? runtime?.authManager ?? CloudRuntime.instance!.authManager,

        _devices =

            deviceManager ?? runtime?.deviceManager ?? CloudRuntime.instance!.deviceManager,

        _storage = runtime?.storage ?? CloudRuntime.instance!.storage;



  final AuthManager _auth;

  final DeviceManager _devices;

  final CloudSecureStorage _storage;



  /// هل الجلسة السحابية جاهزة للمزامنة؟

  Future<bool> isCloudSessionReady() async {

    if (!await _auth.isLoggedIn()) return false;

    if (!await _devices.isRegistered()) return false;

    final companyId = await _storage.readCompanyId();

    final branchId = await _storage.readBranchId();

    final userId = await _storage.readUserId();

    if (companyId == null ||

        companyId.trim().isEmpty ||

        branchId == null ||

        branchId.trim().isEmpty ||

        userId == null ||

        userId.trim().isEmpty) {

      return false;

    }

    return true;

  }



  /// تسجيل دخول بالبريد وكلمة المرور — يستنتج المتجر من الخادم.
  Future<void> signIn({
    required String email,
    required String password,
    String? companyId,
    String? branchId,
  }) async {
    final username = email.trim();
    if (username.isEmpty || password.isEmpty) {
      throw const AuthException(
        code: 'validation_error',
        message: 'Email and password are required',
      );
    }

    await _storage.writeCloudUsername(username);

    final explicitCompany = (companyId ?? '').trim();
    final explicitBranch = (branchId ?? '').trim();
    final hasExplicitTenant =
        explicitCompany.isNotEmpty && explicitBranch.isNotEmpty;

    await _storage.deleteDeviceId();
    if (!hasExplicitTenant) {
      await _storage.deleteCompanyId();
      await _storage.deleteBranchId();
    }

    final installationId = await DeviceBinding.readInstallationId();
    await _storage.writeInstallationId(installationId);

    final loginRequest = LoginRequest(
      username: username,
      password: password,
      companyId: hasExplicitTenant ? explicitCompany : null,
      branchId: hasExplicitTenant ? explicitBranch : null,
      deviceId: null,
      installationId: installationId,
    );

    try {
      await _auth.login(loginRequest);
      await _persistTenantFromStorage();
      await _ensureSelfDeviceRecorded();
      return;
    } on AuthException catch (e) {
      final selection = CloudCompanySelectionRequired.fromAuthException(e);
      if (selection != null) {
        throw selection;
      }
      // معرّف متجر محلي/قديم يُرفض كـ invalid_credentials رغم صحة كلمة المرور.
      if (e.code == 'invalid_credentials' && hasExplicitTenant) {
        await _storage.deleteCompanyId();
        await _storage.deleteBranchId();
        await _signInWithoutExplicitTenant(
          username: username,
          password: password,
          installationId: installationId,
        );
        return;
      }
      switch (e.code) {
        case 'invalid_credentials':
        case 'account_disabled':
        case 'company_suspended':
        case 'forbidden':
          rethrow;
        default:
          break;
      }
    }

    await _auth.loginPairing(
      LoginRequest(
        username: username,
        password: password,
        companyId: hasExplicitTenant ? explicitCompany : null,
        branchId: hasExplicitTenant ? explicitBranch : null,
      ),
    );
    await _persistTenantFromStorage();
    await _ensureSelfDeviceRecorded();
  }

  /// إعادة محاولة الدخول باستنتاج المتجر من البريد فقط (بدون company_id/branch_id).
  Future<void> _signInWithoutExplicitTenant({
    required String username,
    required String password,
    required String installationId,
  }) async {
    try {
      await _auth.login(
        LoginRequest(
          username: username,
          password: password,
          companyId: null,
          branchId: null,
          deviceId: null,
          installationId: installationId,
        ),
      );
      await _persistTenantFromStorage();
      await _ensureSelfDeviceRecorded();
      return;
    } on AuthException catch (e) {
      final selection = CloudCompanySelectionRequired.fromAuthException(e);
      if (selection != null) {
        throw selection;
      }
      switch (e.code) {
        case 'invalid_credentials':
        case 'account_disabled':
        case 'company_suspended':
        case 'forbidden':
          rethrow;
        default:
          break;
      }
    }

    await _auth.loginPairing(
      LoginRequest(
        username: username,
        password: password,
        companyId: null,
        branchId: null,
      ),
    );
    await _persistTenantFromStorage();
    await _ensureSelfDeviceRecorded();
  }

  Future<void> _persistTenantFromStorage() async {

    final companyId = (await _storage.readCompanyId())?.trim() ?? '';

    final branchId = (await _storage.readBranchId())?.trim() ?? '';

    if (companyId.isEmpty || branchId.isEmpty) {

      throw const AuthException(

        code: 'login_invalid_response',

        message: 'Login response missing tenant context',

      );

    }

  }



  Future<void> _ensureSelfDeviceRecorded() async {

    final companyId = (await _storage.readCompanyId())?.trim() ?? '';

    final branchId = (await _storage.readBranchId())?.trim() ?? '';

    final deviceId = (await _storage.readDeviceId())?.trim() ?? '';

    if (companyId.isEmpty || branchId.isEmpty || deviceId.isEmpty) return;



    try {

      final cloudDevice = await _devices.fetchMe();

      final installationId = await DeviceBinding.readInstallationId();

      final platform = DeviceBinding.readDevicePlatform();

      String? appVersion;

      try {

        final info = await PackageInfo.fromPlatform();

        appVersion = info.version;

      } on Object {

        appVersion = null;

      }

      await CloudDeviceLocalStore.upsertSelfDevice(

        device: cloudDevice,

        organizationId: companyId,

        branchId: branchId,

        installationId: installationId,

        deviceName: cloudDevice.deviceName,

        platform: platform,

        osName: platform == 'android' ? 'Android' : 'Windows',

        appVersion: appVersion,

      );

    } on Object {

      // لا نمنع الدخول — شاشة Miza Cloud تستكمل الاسم لاحقاً.

    }

  }



  /// طلب كلمة مرور مؤقتة لحساب Miza Cloud عبر البريد.
  Future<void> requestPasswordReset({required String email}) async {
    await _auth.requestPasswordReset(email: email);
  }



  /// تسجيل الجهاز على السحابة وحفظه محلياً.

  Future<void> registerThisDevice({String? deviceName}) async {

    final companyId = await _storage.readCompanyId();

    final branchId = await _storage.readBranchId();

    if (companyId == null ||

        companyId.isEmpty ||

        branchId == null ||

        branchId.isEmpty) {

      throw const DeviceException(

        code: 'validation_error',

        message: 'Missing company or branch context',

      );

    }



    String? appVersion;

    try {

      final info = await PackageInfo.fromPlatform();

      appVersion = info.version;

    } on Object {

      appVersion = null;

    }



    final result = await _devices.register(

      companyId: companyId,

      branchId: branchId,

      deviceName: deviceName,

      appVersion: appVersion,

    );



    final installationId = await DeviceBinding.readInstallationId();

    await CloudDeviceLocalStore.upsertSelfDevice(

      device: result.device,

      organizationId: companyId,

      branchId: branchId,

      installationId: installationId,

      deviceName: deviceName ?? result.device.deviceName,

      platform: DeviceBinding.readDevicePlatform(),

      osName: DeviceBinding.readDevicePlatform() == 'android'

          ? 'Android'

          : 'Windows',

      appVersion: appVersion,

    );

  }



  Future<void> signOut() async {

    await _auth.logout();

  }

}



