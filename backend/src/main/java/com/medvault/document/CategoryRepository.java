package com.medvault.document;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CategoryRepository extends JpaRepository<Category, Short> {
    Optional<Category> findByCode(String code);
    List<Category> findByActiveTrueOrderBySortOrderAsc();
}
