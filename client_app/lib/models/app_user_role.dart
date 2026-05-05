enum AppUserRole {
  citizen,
  driver,
  admin,
}

AppUserRole parseUserRole(String? rawRole) {
  switch (rawRole) {
    case 'driver':
      return AppUserRole.driver;
    case 'admin':
      return AppUserRole.admin;
    case 'citizen':
    default:
      return AppUserRole.citizen;
  }
}

String roleLabel(AppUserRole role) {
  switch (role) {
    case AppUserRole.driver:
      return 'Driver';
    case AppUserRole.admin:
      return 'Admin';
    case AppUserRole.citizen:
      return 'Citizen';
  }
}
