package com.medvault.document;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface DocumentRepository extends JpaRepository<Document, UUID> {
    List<Document> findByPatient_IdOrderByVisitDateDesc(UUID patientId);
    List<Document> findByPatient_IdAndCategory_Id(UUID patientId, Short categoryId);
}
