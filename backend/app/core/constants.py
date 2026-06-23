from enum import Enum


class OrganizationStatus(str, Enum):
    ACTIVE = "ACTIVE"
    SUSPENDED = "SUSPENDED"
    DEACTIVATED = "DEACTIVATED"


class UserRole(str, Enum):
    ADMIN = "ADMIN"
    FACULTY = "FACULTY"
    SYSTEM = "SYSTEM"


class UserStatus(str, Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    PENDING_APPROVAL = "PENDING_APPROVAL"


class DevicePlatform(str, Enum):
    ANDROID = "ANDROID"
    IOS = "IOS"


class LocationEventType(str, Enum):
    ENTER_CAMPUS = "ENTER_CAMPUS"
    EXIT_CAMPUS = "EXIT_CAMPUS"
    RETURN_CAMPUS = "RETURN_CAMPUS"


class RequestStatus(str, Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class NotificationType(str, Enum):
    EXIT_ALERT = "EXIT_ALERT"
    REMINDER_1 = "REMINDER_1"
    REMINDER_2 = "REMINDER_2"
    REMINDER_3 = "REMINDER_3"
    DEVICE_ALERT = "DEVICE_ALERT"


class NotificationStatus(str, Enum):
    SENT = "SENT"
    READ = "READ"
    FAILED = "FAILED"


class AttendanceStatus(str, Enum):
    PRESENT = "PRESENT"
    HALF_DAY = "HALF_DAY"
    ABSENT = "ABSENT"


class FacultyRegistrationMode(str, Enum):
    AUTO_APPROVE = "AUTO_APPROVE"
    ADMIN_APPROVAL = "ADMIN_APPROVAL"
