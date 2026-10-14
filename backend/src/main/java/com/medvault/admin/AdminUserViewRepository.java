package com.medvault.admin;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.repository.Repository;

import java.util.Optional;
import java.util.UUID;

@org.springframework.stereotype.Repository
public interface AdminUserViewRepository extends Repository<AdminUserView, UUID> {

    Optional<AdminUserView> findById(UUID id);

    Optional<AdminUserView> findByEmail(String email);

    boolean existsById(UUID id);

    long count();

    Page<AdminUserView> findAll(Pageable pageable);

    Page<AdminUserView> findByRole(String role, Pageable pageable);

    Page<AdminUserView> findByStatus(String status, Pageable pageable);

    Page<AdminUserView> findByVerificationStatus(String verificationStatus, Pageable pageable);
}
