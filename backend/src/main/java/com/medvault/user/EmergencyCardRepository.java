package com.medvault.user;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface EmergencyCardRepository extends JpaRepository<EmergencyCard, UUID> {
    Optional<EmergencyCard> findByTokenHash(String tokenHash);
}
