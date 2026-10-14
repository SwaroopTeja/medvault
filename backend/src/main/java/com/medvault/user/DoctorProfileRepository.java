package com.medvault.user;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface DoctorProfileRepository extends JpaRepository<DoctorProfile, UUID> {
    Optional<DoctorProfile> findByRegistrationCouncilAndRegistrationNumber(String registrationCouncil, String registrationNumber);
    List<DoctorProfile> findByVerificationStatus(DoctorVerificationStatus verificationStatus);
}
