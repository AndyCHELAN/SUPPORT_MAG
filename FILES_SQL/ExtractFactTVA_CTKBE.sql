
/*
	.DESCRIPTION
		Cette requête permet d'extraire les factures CTK avec un numéro de TVA Belge edité sur un magasin Belge. (IdMag > 800)
        Elle balaye tous les champs pour trouver le numéro de TVA et afficher le champ qui le contient.
        
            * La fonction recherche la chaîne "TVA" ou "BE" suivi de 6 chiffres.
            * Si le numéro de TVA est dans le champ NumTVA, alors le champ TVA Renseigné affichera "OK".
            * Si le numéro de TVA est dans un autre champ, alors le champ TVA Renseigné affichera la valeur trouvée.

        Elle recupère également les montants de TVA à 21% et 6% pour chaque facture.

		Environnement : CENTRAKOR BE

	.PREREQUISITES
		* A exécuter sur l'instance SQL SVP1GSMSQL-STD, base AGILServer_CTK
        * Remplacer GETDATE() par la date souhaitée si besoin.

	.NOTE 
		Fichier : ExtractFactTVA_CTKBE.sql
		Auteur : CHELAN Andy
		Version : 2.0
		Date : 24/02/2026
*/

USE AGILServer_CTK

DECLARE @Date AS DATE = GETDATE()

------------------------------------------------------------------
       --- EXTRACTION DES FACTURES AVEC VALEURS TVA BE --- 
------------------------------------------------------------------

;WITH FACTS AS (
    SELECT
        F.NumFact AS NoTicket,
        F.Date_Facture,
        F.IdMag,
        M.Nom AS Magasin,
        F.Civilite,
        F.Nom, 
        F.Prenom,
        F.Cpos,
        F.Ville,
        F.Adr1,
        F.Adr2,
        F.Adr3,
        F.Adr4,
        F.EmailCli,
        C.IdDynInfo_SIRET AS NumSIRET,
        F.NumTVA,
        V.ValeurTVA,
        V.ChampTVA, 
        F.TotalTTC,
        ROW_NUMBER() OVER (
            PARTITION BY F.NumFact 
            ORDER BY 
                CASE 
                    WHEN V.ChampTVA = 'NumTVA' THEN 1
                    WHEN V.ChampTVA = 'NumSIRET' THEN 2
                    ELSE 3
                END
        ) AS RN
    FROM FACTURE F

    INNER JOIN Magasin M 
        ON M.IdMag = F.IdMag

    LEFT JOIN CUST_CONTACT C 
        ON C.IdCust = F.IdCust

    CROSS APPLY (
        VALUES
            ('Addr1', F.Adr1),
            ('Addr2', F.Adr2),
            ('Addr3', F.Adr3),
            ('Addr4', F.Adr4),
            ('TelCli',F.TelCli),
            ('EmailCli',F.EmailCli),
            ('Adr1Facturation',F.Adr1Facturation),
            ('Adr2Facturation',F.Adr2Facturation),
            ('Adr3Facturation',F.Adr3Facturation),
            ('Adr4Facturation',F.Adr4Facturation),
            ('TelCliFacturation',F.TelCliFacturation),
            ('NumSIRET', C.IdDynInfo_SIRET),
            ('NumTVA',F.NumTva),
            ('EmailCliFacturation',F.EmailCliFacturation)
    ) V(ChampTVA, ValeurTVA)

    WHERE F.IdMag > 800
        AND V.ValeurTVA NOT LIKE '%@%'
        AND (
               V.ValeurTVA LIKE '%TVA%'
            OR V.ValeurTVA LIKE '%BE%[0-9][0-9][0-9][0-9][0-9][0-9]%'
        )
        AND F.Date_Facture = @Date
)

SELECT *
INTO #TEMP_TVA_FACT
FROM FACTS
WHERE RN = 1
ORDER BY NoTicket

------------------------------------------------------------------
           --- CREATION TABLE TEMPORAIRE TVA 21 --- 
------------------------------------------------------------------

CREATE TABLE #TVA21 (
    Noticket VARCHAR(20),
    TVA21 DECIMAL(19,4)
)

--- Insertion factures avec TVA 21% ---

INSERT INTO #TVA21
SELECT VTE.NoTicket, SUM(VTELIG.ValTVA)
FROM VTELIG
INNER JOIN VTE ON VTE.IdVte = VTELIG.IdVte
WHERE VTELIG.TauxTVA = '21'
    AND VTE.NoTicket IN (
        SELECT DISTINCT NoTicket 
        FROM #TEMP_TVA_FACT
    )
GROUP BY VTE.NoTicket

--- Insertion factures sans TVA 21% ---

INSERT INTO #TVA21
SELECT #TEMP_TVA_FACT.Noticket, '0'
FROM #TEMP_TVA_FACT
LEFT JOIN #TVA21 ON #TVA21.NoTicket = #TEMP_TVA_FACT.Noticket
WHERE #TEMP_TVA_FACT.Noticket NOT IN (
    SELECT #TVA21.NoTicket 
    FROM #TVA21
) 

------------------------------------------------------------------
           --- CREATION TABLE TEMPORAIRE TVA 6 --- 
------------------------------------------------------------------

--- Insertion factures avec TVA 6% ---

CREATE TABLE #TVA6 (
    Noticket VARCHAR(20),
    TVA6 DECIMAL(19,4)
)

INSERT INTO #TVA6
SELECT VTE.NoTicket, SUM(VTELIG.ValTVA)
FROM VTELIG
INNER JOIN VTE ON VTE.IdVte = VTELIG.IdVte
WHERE VTELIG.TauxTVA = '6'
    AND VTE.NoTicket IN (
        SELECT DISTINCT NoTicket 
        FROM #TEMP_TVA_FACT
    )
GROUP BY VTE.NoTicket

--- Insertion factures sans TVA 6% ---

INSERT INTO #TVA6
SELECT #TEMP_TVA_FACT.Noticket, '0'
FROM #TEMP_TVA_FACT
LEFT JOIN #TVA6 ON #TVA6.NoTicket = #TEMP_TVA_FACT.Noticket
WHERE #TEMP_TVA_FACT.Noticket NOT IN (
    SELECT #TVA6.NoTicket 
    FROM #TVA6
) 

------------------------------------------------------------------
                    --- SELECT FINAL --- 
------------------------------------------------------------------


SELECT 
    F.Noticket            AS 'Numéro Facture',
    F.Date_Facture        AS 'Date Facture',
    F.IdMag               AS 'N° Magasin',
    F.Magasin             AS 'Nom Magasin',
    ISNULL(F.Civilite,'') AS 'Civilité',
    ISNULL(F.Nom,'')      AS 'Nom', 
    ISNULL(F.Prenom,'')   AS 'Prénom',
    ISNULL(F.Cpos,'')     AS 'Code Postal',
    ISNULL(F.Ville,'')    AS 'Ville',
    ISNULL(F.Adr1,'')     AS 'Adresse 1',
    ISNULL(F.Adr2,'')     AS 'Adresse 2',
    ISNULL(F.Adr3,'')     AS 'Adresse 3',
    ISNULL(F.Adr4,'')     AS 'Adresse 4',
    ISNULL(F.EmailCli,'') AS 'E-Mail',
    ISNULL(F.NumSIRET,'') AS 'N° SIRET',
    ISNULL(F.NumTVA,'')   AS 'N° TVA',
    --F.ValeurTVA     AS 'N° TVA Renseigné',
    --F.ChampTVA      AS 'Champ TVA Renseigné',
    CASE WHEN F.NumTVA = F.ValeurTVA THEN 'OK' ELSE F.ValeurTVA END AS 'N° TVA Renseigné',
    CASE WHEN F.ChampTVA = 'NumTVA' THEN 'OK' ELSE F.ChampTVA END AS 'Champ TVA Renseigné',
    #TVA21.TVA21    AS 'TVA 21%',
    #TVA6.TVA6      AS 'TVA 6%',
    F.TotalTTC      AS 'Total TTC'

FROM #TEMP_TVA_FACT F

INNER JOIN #TVA21 
    ON #TVA21.NoTicket = F.Noticket
INNER JOIN #TVA6 
    ON #TVA6.NoTicket = F.Noticket

ORDER BY 
    F.IdMag, 
    F.Date_Facture, 
    F.Noticket

------------------------------------------------------------------
                    --- DROP TABLE TEMP --- 
------------------------------------------------------------------

DROP TABLE #TEMP_TVA_FACT
DROP TABLE #TVA21
DROP TABLE #TVA6