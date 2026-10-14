package com.medvault.sharing;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface AccessGrantRepository extends JpaRepository<AccessGrant, UUID> {
    Optional<AccessGrant> findByTokenHash(String tokenHash);
    List<AccessGrant> findByPatient_IdAndStatus(UUID patientId, GrantStatus status);
    List<AccessGrant> findByDoctor_IdAndStatus(UUID doctorId, GrantStatus status);
}
