package com.medvault.admin;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import org.hibernate.annotations.Immutable;

import com.medvault.user.PatientHealthInfo;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "v_admin_users")
@Immutable
@Getter
public class AdminUserView {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "email", nullable = false)
    private String email;

    @Column(name = "role", length = 20, nullable = false)
    private String role;

    @Column(name = "status", length = 30, nullable = false)
    private String status;

    @Column(name = "mfa_enabled", nullable = false)
    private boolean mfaEnabled;

    @Column(name = "last_login_at")
    private Instant lastLoginAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "full_name", length = 150)
    private String fullName;

    @Column(name = "registration_number", length = 50)
    private String registrationNumber;

    @Column(name = "registration_council", length = 100)
    private String registrationCouncil;

    @Column(name = "specialization", length = 100)
    private String specialization;

    @Column(name = "verification_status", length = 10)
    private String verificationStatus;

}
