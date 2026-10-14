package com.medvault.notification;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface NotificationRepository extends JpaRepository<Notification, UUID> {
    List<Notification> findByUser_IdAndReadAtIsNullOrderByCreatedAtDesc(UUID userId);
    List<Notification> findByUser_IdOrderByCreatedAtDesc(UUID userId);
}
