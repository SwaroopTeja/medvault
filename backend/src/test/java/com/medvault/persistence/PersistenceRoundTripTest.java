package com.medvault.persistence;

import com.medvault.admin.AdminUserView;
import com.medvault.admin.AdminUserViewRepository;
import com.medvault.audit.AuditLog;
import com.medvault.audit.AuditLogRepository;
import com.medvault.auth.RefreshToken;
import com.medvault.auth.RefreshTokenRepository;
import com.medvault.document.Category;
import com.medvault.document.CategoryRepository;
import com.medvault.document.ClassifiedBy;
import com.medvault.document.Document;
import com.medvault.document.DocumentRepository;
import com.medvault.document.DocumentStatus;
import com.medvault.notification.Notification;
import com.medvault.notification.NotificationRepository;
import com.medvault.sharing.AccessGrant;
import com.medvault.sharing.AccessGrantRepository;
import com.medvault.sharing.GrantStatus;
import com.medvault.user.DoctorProfile;
import com.medvault.user.DoctorProfileRepository;
import com.medvault.user.DoctorVerificationStatus;
import com.medvault.user.EmergencyCard;
import com.medvault.user.EmergencyCardRepository;
import com.medvault.user.PatientHealthInfo;
import com.medvault.user.PatientHealthInfoRepository;
import com.medvault.user.PatientProfile;
import com.medvault.user.PatientProfileRepository;
import com.medvault.user.User;
import com.medvault.user.UserRepository;
import com.medvault.user.UserRole;
import com.medvault.user.UserStatus;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Testcontainers
class PersistenceRoundTripTest {

    static {
        System.setProperty("api.version", "1.44");
        System.setProperty("user.timezone", "UTC");
        java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"));
    }

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PatientProfileRepository patientProfileRepository;

    @Autowired
    private PatientHealthInfoRepository patientHealthInfoRepository;

    @Autowired
    private DoctorProfileRepository doctorProfileRepository;

    @Autowired
    private EmergencyCardRepository emergencyCardRepository;

    @Autowired
    private RefreshTokenRepository refreshTokenRepository;

    @Autowired
    private CategoryRepository categoryRepository;

    @Autowired
    private DocumentRepository documentRepository;

    @Autowired
    private AccessGrantRepository accessGrantRepository;

    @Autowired
    private NotificationRepository notificationRepository;

    @Autowired
    private AuditLogRepository auditLogRepository;

    @Autowired
    private AdminUserViewRepository adminUserViewRepository;

    @Autowired
    private EntityManager entityManager;

    private static final String SHA256_A = "a".repeat(64);
    private static final String SHA256_B = "b".repeat(64);
    private static final String SHA256_C = "c".repeat(64);
    private static final String SHA256_D = "d".repeat(64);

    @Test
    @Transactional
    void testAllEntitiesPersistenceRoundTrip() {
        // 1. Verify Flyway seeded categories and create a custom Category with JSON keywords
        List<Category> seededCategories = categoryRepository.findAll();
        assertThat(seededCategories).isNotEmpty();
        Category heartCategory = categoryRepository.findByCode("HEART").orElseThrow();
        assertThat(heartCategory.getKeywords()).contains("ecg", "ekg");

        Category customCategory = new Category();
        customCategory.setCode("CUSTOM");
        customCategory.setLabel("Custom Category");
        customCategory.setSortOrder(99);
        customCategory.setActive(true);
        customCategory.setKeywords(List.of("tag1", "tag2", "tag3"));
        customCategory = categoryRepository.save(customCategory);

        // 2. User & PatientProfile & PatientHealthInfo
        User patientUser = new User();
        patientUser.setEmail("patient@example.com");
        patientUser.setPasswordHash("$2a$10$hashedPasswordHere");
        patientUser.setRole(UserRole.PATIENT);
        patientUser.setStatus(UserStatus.ACTIVE);
        patientUser.setMfaEnabled(false);
        patientUser = userRepository.save(patientUser);

        PatientProfile patientProfile = new PatientProfile();
        patientProfile.setUser(patientUser);
        patientProfile.setFullName("John Doe");
        patientProfile.setDateOfBirth(LocalDate.of(1990, 1, 15));
        patientProfile.setGender("MALE");
        patientProfile.setPhone("+919876543210");
        patientProfile = patientProfileRepository.save(patientProfile);

        PatientHealthInfo healthInfo = new PatientHealthInfo();
        healthInfo.setUser(patientUser);
        healthInfo.setBloodGroup("O+");
        healthInfo.setAllergies("Penicillin");
        healthInfo.setChronicConditions("Asthma");
        healthInfo.setEmergencyContactName("Jane Doe");
        healthInfo.setEmergencyContactPhone("+919876543211");
        healthInfo = patientHealthInfoRepository.save(healthInfo);

        // 3. EmergencyCard
        EmergencyCard emergencyCard = new EmergencyCard();
        emergencyCard.setPatient(patientUser);
        emergencyCard.setTokenHash(SHA256_A);
        emergencyCard.setEnabled(true);
        emergencyCard = emergencyCardRepository.save(emergencyCard);

        // 4. RefreshToken
        RefreshToken refreshToken = new RefreshToken();
        refreshToken.setUser(patientUser);
        refreshToken.setTokenHash(SHA256_B);
        refreshToken.setFamilyId(UUID.randomUUID());
        refreshToken.setExpiresAt(Instant.now().plus(7, ChronoUnit.DAYS));
        refreshToken = refreshTokenRepository.save(refreshToken);

        // 5. Doctor User & DoctorProfile
        User doctorUser = new User();
        doctorUser.setEmail("doctor@example.com");
        doctorUser.setPasswordHash("$2a$10$hashedDoctorPassword");
        doctorUser.setRole(UserRole.DOCTOR);
        doctorUser.setStatus(UserStatus.PENDING_VERIFICATION);
        doctorUser.setMfaEnabled(true);
        doctorUser = userRepository.save(doctorUser);

        DoctorProfile doctorProfile = new DoctorProfile();
        doctorProfile.setUser(doctorUser);
        doctorProfile.setFullName("Dr. Alice Smith");
        doctorProfile.setRegistrationNumber("REG-12345");
        doctorProfile.setRegistrationCouncil("State Medical Council");
        doctorProfile.setSpecialization("Cardiology");
        doctorProfile.setLicenseDocumentKey("licenses/doc-12345.pdf");
        doctorProfile.setVerificationStatus(DoctorVerificationStatus.PENDING);
        doctorProfile = doctorProfileRepository.save(doctorProfile);

        // 6. Document
        Document document = new Document();
        document.setPatient(patientUser);
        document.setCategory(heartCategory);
        document.setTitle("ECG Report");
        document.setVisitDate(LocalDate.of(2026, 5, 20));
        document.setDoctorName("Dr. Alice Smith");
        document.setHospitalName("City General Hospital");
        document.setOriginalFilename("ecg_scan.pdf");
        document.setMimeType("application/pdf");
        document.setSizeBytes(1048576L);
        document.setStorageKey("docs/patient-1/ecg_scan.pdf");
        document.setWrappedDataKey("encryptedKeyBytes".getBytes(StandardCharsets.UTF_8));
        document.setKeyVersion(1);
        document.setChecksumSha256(SHA256_C);
        document.setExtractedText("Normal sinus rhythm, troponin negative");
        document.setOcrConfidence(new BigDecimal("0.985"));
        document.setClassifiedBy(ClassifiedBy.RULES);
        document.setStatus(DocumentStatus.READY);
        document = documentRepository.save(document);

        // 7. AccessGrant with ManyToMany Categories
        AccessGrant accessGrant = new AccessGrant();
        accessGrant.setPatient(patientUser);
        accessGrant.setDoctor(doctorUser);
        accessGrant.setTokenHash(SHA256_D);
        accessGrant.setStatus(GrantStatus.ACTIVE);
        accessGrant.setDurationMinutes(30);
        accessGrant.setTotalExtendedMinutes(0);
        accessGrant.setClaimExpiresAt(Instant.now().plus(5, ChronoUnit.MINUTES));
        accessGrant.setActivatedAt(Instant.now());
        accessGrant.setExpiresAt(Instant.now().plus(30, ChronoUnit.MINUTES));
        accessGrant.setCategories(Set.of(heartCategory, customCategory));
        accessGrant = accessGrantRepository.save(accessGrant);

        // 8. Notification with JSON payload
        Notification notification = new Notification();
        notification.setUser(patientUser);
        notification.setType("GRANT_CLAIMED");
        notification.setPayload(Map.of(
            "grantId", accessGrant.getId().toString(),
            "doctorName", "Dr. Alice Smith"
        ));
        notification = notificationRepository.save(notification);

        // 9. AuditLog with JSON metadata (append-only table)
        AuditLog auditLog = new AuditLog();
        auditLog.setActorId(doctorUser.getId());
        auditLog.setActorRole("DOCTOR");
        auditLog.setAction("GRANT_CLAIM");
        auditLog.setTargetType("ACCESS_GRANT");
        auditLog.setTargetId(accessGrant.getId());
        auditLog.setSubjectUserId(patientUser.getId());
        auditLog.setGrantId(accessGrant.getId());
        auditLog.setIp("127.0.0.1");
        auditLog.setUserAgent("Mozilla/5.0 MedVault/1.0");
        auditLog.setMetadata(Map.of("claimMethod", "QR_SCAN", "success", true));
        auditLog = auditLogRepository.save(auditLog);

        // Flush and clear EntityManager to ensure subsequent queries read fresh from database
        entityManager.flush();
        entityManager.clear();

        // 10. Reload and Assert All Entities

        // Reload Custom Category
        Category reloadedCategory = categoryRepository.findById(customCategory.getId()).orElseThrow();
        assertThat(reloadedCategory.getCode()).isEqualTo("CUSTOM");
        assertThat(reloadedCategory.getKeywords()).containsExactly("tag1", "tag2", "tag3");

        // Reload User & PatientProfile & HealthInfo
        User reloadedUser = userRepository.findById(patientUser.getId()).orElseThrow();
        assertThat(reloadedUser.getEmail()).isEqualTo("patient@example.com");
        assertThat(reloadedUser.getCreatedAt()).isNotNull();
        assertThat(reloadedUser.getUpdatedAt()).isNotNull();

        PatientProfile reloadedProfile = patientProfileRepository.findById(patientUser.getId()).orElseThrow();
        assertThat(reloadedProfile.getFullName()).isEqualTo("John Doe");
        assertThat(reloadedProfile.getDateOfBirth()).isEqualTo(LocalDate.of(1990, 1, 15));
        assertThat(reloadedProfile.getCreatedAt()).isNotNull();

        PatientHealthInfo reloadedHealth = patientHealthInfoRepository.findById(patientUser.getId()).orElseThrow();
        assertThat(reloadedHealth.getBloodGroup()).isEqualTo("O+");
        assertThat(reloadedHealth.getAllergies()).isEqualTo("Penicillin");
        assertThat(reloadedHealth.getUpdatedAt()).isNotNull();

        // Reload EmergencyCard
        EmergencyCard reloadedCard = emergencyCardRepository.findById(patientUser.getId()).orElseThrow();
        assertThat(reloadedCard.getTokenHash()).isEqualTo(SHA256_A);
        assertThat(reloadedCard.isEnabled()).isTrue();
        assertThat(reloadedCard.getCreatedAt()).isNotNull();

        // Reload RefreshToken
        RefreshToken reloadedToken = refreshTokenRepository.findById(refreshToken.getId()).orElseThrow();
        assertThat(reloadedToken.getTokenHash()).isEqualTo(SHA256_B);
        assertThat(reloadedToken.getCreatedAt()).isNotNull();

        // Reload DoctorProfile
        DoctorProfile reloadedDoctorProfile = doctorProfileRepository.findById(doctorUser.getId()).orElseThrow();
        assertThat(reloadedDoctorProfile.getFullName()).isEqualTo("Dr. Alice Smith");
        assertThat(reloadedDoctorProfile.getRegistrationNumber()).isEqualTo("REG-12345");
        assertThat(reloadedDoctorProfile.getVerificationStatus()).isEqualTo(DoctorVerificationStatus.PENDING);
        assertThat(reloadedDoctorProfile.getCreatedAt()).isNotNull();

        // Reload Document
        Document reloadedDoc = documentRepository.findById(document.getId()).orElseThrow();
        assertThat(reloadedDoc.getTitle()).isEqualTo("ECG Report");
        assertThat(reloadedDoc.getChecksumSha256()).isEqualTo(SHA256_C);
        assertThat(reloadedDoc.getWrappedDataKey()).isEqualTo("encryptedKeyBytes".getBytes(StandardCharsets.UTF_8));
        assertThat(reloadedDoc.getStatus()).isEqualTo(DocumentStatus.READY);
        assertThat(reloadedDoc.getOcrConfidence()).isEqualByComparingTo(new BigDecimal("0.985"));
        assertThat(reloadedDoc.getCreatedAt()).isNotNull();
        assertThat(reloadedDoc.getUpdatedAt()).isNotNull();

        // Reload AccessGrant
        AccessGrant reloadedGrant = accessGrantRepository.findById(accessGrant.getId()).orElseThrow();
        assertThat(reloadedGrant.getTokenHash()).isEqualTo(SHA256_D);
        assertThat(reloadedGrant.getStatus()).isEqualTo(GrantStatus.ACTIVE);
        assertThat(reloadedGrant.getCategories()).hasSize(2);
        assertThat(reloadedGrant.getCreatedAt()).isNotNull();

        // Reload Notification
        Notification reloadedNotification = notificationRepository.findById(notification.getId()).orElseThrow();
        assertThat(reloadedNotification.getType()).isEqualTo("GRANT_CLAIMED");
        assertThat(reloadedNotification.getPayload()).containsEntry("doctorName", "Dr. Alice Smith");
        assertThat(reloadedNotification.getCreatedAt()).isNotNull();

        // Reload AuditLog
        AuditLog reloadedAudit = auditLogRepository.findById(auditLog.getId()).orElseThrow();
        assertThat(reloadedAudit.getAction()).isEqualTo("GRANT_CLAIM");
        assertThat(reloadedAudit.getMetadata()).containsEntry("claimMethod", "QR_SCAN");
        assertThat(reloadedAudit.getCreatedAt()).isNotNull();

        // 11. Read from Admin View (v_admin_users)
        Optional<AdminUserView> adminViewPatient = adminUserViewRepository.findById(patientUser.getId());
        assertThat(adminViewPatient).isPresent();
        assertThat(adminViewPatient.get().getEmail()).isEqualTo("patient@example.com");
        assertThat(adminViewPatient.get().getFullName()).isEqualTo("John Doe");
        assertThat(adminViewPatient.get().getRole()).isEqualTo("PATIENT");

        Optional<AdminUserView> adminViewDoctor = adminUserViewRepository.findById(doctorUser.getId());
        assertThat(adminViewDoctor).isPresent();
        assertThat(adminViewDoctor.get().getEmail()).isEqualTo("doctor@example.com");
        assertThat(adminViewDoctor.get().getFullName()).isEqualTo("Dr. Alice Smith");
        assertThat(adminViewDoctor.get().getRegistrationNumber()).isEqualTo("REG-12345");
        assertThat(adminViewDoctor.get().getVerificationStatus()).isEqualTo("PENDING");

        // Verify read-only paged finders on AdminUserViewRepository
        org.springframework.data.domain.Page<AdminUserView> pagedUsers = adminUserViewRepository.findAll(
            org.springframework.data.domain.PageRequest.of(0, 10)
        );
        assertThat(pagedUsers.getContent()).hasSize(2);

        org.springframework.data.domain.Page<AdminUserView> pagedPatients = adminUserViewRepository.findByRole(
            "PATIENT", org.springframework.data.domain.PageRequest.of(0, 10)
        );
        assertThat(pagedPatients.getContent()).hasSize(1);
        assertThat(pagedPatients.getContent().getFirst().getEmail()).isEqualTo("patient@example.com");
    }
}
