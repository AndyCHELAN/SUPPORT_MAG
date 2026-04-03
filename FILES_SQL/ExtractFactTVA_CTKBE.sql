
/*
	.DESCRIPTION
		Cette requête permet d'extraire les factures CTK comportant un numéro de TVA belge
		édité sur un magasin belge (IdMag > 800).

		Elle balaye l'ensemble des champs afin de détecter un numéro de TVA et d'indiquer
		le champ dans lequel celui-ci a été trouvé.

		Règles de contrôle :
			* Recherche la chaîne "TVA" ou "BE" suivie de 6 chiffres.
			* Si le numéro de TVA est présent dans le champ NumTVA, alors le champ
			  [TVA Renseignée] affichera "OK".
			* Si le numéro de TVA est trouvé dans un autre champ, alors le champ
			  [TVA Renseignée] affichera la valeur détectée.

		La requête récupère également les montants de TVA à 21 % et 6 % pour chaque facture.

		Environnement : CENTRAKOR BE

	.PREREQUISITES
		* À exécuter sur l'instance SQL : SVP1GSMSQL-STD
		* Base de données : AGILServer_CTK
		* Remplacer GETDATE() par la date souhaitée si nécessaire

	.NOTE
		Fichier : ExtractFactTVA_CTKBE.sql
		Auteur  : CHELAN Andy
        Version : 3.0

	.HISTORIQUE
		+---------+------------+--------------+----------------------------------- -----------------+
		| Version | Date       | Auteur       | Modifications                                       |
		+---------+------------+--------------+----------------------------------- -----------------+
		| 3.0     | 02/04/2026 | CHELAN Andy  | Ajout des champs [Date Vente]                       |
        |         |            |              | Extraction des Mode de Paiement par facture         |
        |         |            |              |                                                     |
		| 2.0     | 24/02/2026 | CHELAN Andy  | Ajout du champ [N° SIRET]                           |
		| 1.0     | 01/01/2026 | CHELAN Andy  | Création du script                                  |
		+---------+------------+--------------+-----------------------------------------------------+
*/

USE AGILServer_CTK

DECLARE @Date AS DATE = GETDATE()

------------------------------------------------------------------
       --- EXTRACTION DES FACTURES AVEC VALEURS TVA BE --- 
------------------------------------------------------------------

--- Identification des factures concernées ---

;WITH FACTS AS (
    SELECT
        F.NumFact AS NoTicket,
        F.Date_Facture,
        F.DateVente,
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

    WHERE 
        F.IdMag > 800
        AND V.ValeurTVA NOT LIKE '%@%'
        AND (
               V.ValeurTVA LIKE '%TVA%'
            OR V.ValeurTVA LIKE '%BE%[0-9][0-9][0-9][0-9][0-9][0-9]%'
        )
        AND F.Date_Facture = @Date
)

--- Insertion des factures concernées dans TEMP_TVA_FACT ---

SELECT *
INTO #TEMP_TVA_FACT
FROM FACTS
WHERE RN = 1
ORDER BY NoTicket

------------------------------------------------------------------
           --- EXTRACTION DES FACTURES TVA 21 --- 
------------------------------------------------------------------

--- Création table temporaire TVA21 ---

CREATE TABLE #TVA21 (
    Noticket VARCHAR(20),
    TVA21 DECIMAL(19,4)
)

--- Insertion factures avec TVA 21% ---

INSERT INTO #TVA21
SELECT 
    VTE.NoTicket, 
    SUM(VTELIG.ValTVA)
FROM VTELIG
INNER JOIN VTE 
    ON VTE.IdVte = VTELIG.IdVte
WHERE VTELIG.TauxTVA = '21'
    AND VTE.NoTicket IN (
        SELECT 
            DISTINCT NoTicket 
        FROM #TEMP_TVA_FACT
    )
GROUP BY 
    VTE.NoTicket

--- Insertion factures sans TVA 21% ---

INSERT INTO #TVA21
SELECT 
    #TEMP_TVA_FACT.Noticket, 
     '0'
FROM #TEMP_TVA_FACT
LEFT JOIN #TVA21 
    ON #TVA21.NoTicket = #TEMP_TVA_FACT.Noticket
WHERE #TEMP_TVA_FACT.Noticket NOT IN (
    SELECT 
        #TVA21.NoTicket 
    FROM #TVA21
) 

------------------------------------------------------------------
           --- EXTRACTION DES FACTURES TVA 6 --- 
------------------------------------------------------------------

--- Création table temporaire TVA6 ---

CREATE TABLE #TVA6 (
    Noticket VARCHAR(20),
    TVA6 DECIMAL(19,4)
)

--- Insertion factures avec TVA 6% ---

INSERT INTO #TVA6
SELECT 
    VTE.NoTicket, 
    SUM(VTELIG.ValTVA)
FROM VTELIG
INNER JOIN VTE 
    ON VTE.IdVte = VTELIG.IdVte
WHERE VTELIG.TauxTVA = '6'
    AND VTE.NoTicket IN (
        SELECT 
            DISTINCT NoTicket 
        FROM #TEMP_TVA_FACT
    )
GROUP BY 
    VTE.NoTicket

--- Insertion factures sans TVA 6% ---

INSERT INTO #TVA6
SELECT 
    #TEMP_TVA_FACT.
    Noticket, '0'
FROM #TEMP_TVA_FACT
LEFT JOIN #TVA6 
    ON #TVA6.NoTicket = #TEMP_TVA_FACT.Noticket
WHERE #TEMP_TVA_FACT.Noticket NOT IN (
    SELECT 
        #TVA6.NoTicket 
    FROM #TVA6
) 

------------------------------------------------------------------
           --- EXTRACTION DES MODE DE PAIEMENT  --- 
------------------------------------------------------------------

--- Création table temporaires MODE_PAIEMENT ---

CREATE TABLE #MODE_PAIEMENT (
    Noticket        VARCHAR(20),
    ModePaiement    VARCHAR(50),
    MontantPaiment  DECIMAL(19,4),
    NumLigne        VARCHAR(10)
);

--- Insertion des modes de paiement ---

INSERT INTO #MODE_PAIEMENT
SELECT
    TRS.NoTicket,
    TRSLIG.Lib,
    SUM(Montant) AS Montant,
    ROW_NUMBER() OVER (
        PARTITION BY TRS.NoTicket
        ORDER BY TRSLIG.Lib
    ) AS NumLigne
FROM TRSLIG
INNER JOIN TRS
    ON TRS.IdTrs = TRSLIG.IdTrs
WHERE TRS.NoTicket IN (
    SELECT NoTicket
    FROM #TEMP_TVA_FACT
)
AND TRSLIG.Nature = '00'

GROUP BY
    TRS.NoTicket, 
    TRSLIG.Lib

--- Création tables temporaire MODE_PAIEMENTX ---

CREATE TABLE #MODE_PAIEMENT1 (
    Noticket        VARCHAR(20),
    ModePaiement    VARCHAR(50),
    MontantPaiment  DECIMAL(19,4),
);

CREATE TABLE #MODE_PAIEMENT2 (
    Noticket        VARCHAR(20),
    ModePaiement    VARCHAR(50),
    MontantPaiment  DECIMAL(19,4),
);

CREATE TABLE #MODE_PAIEMENT3 (
    Noticket        VARCHAR(20),
    ModePaiement    VARCHAR(50),
    MontantPaiment  DECIMAL(19,4),
)

--- Insertion des lignes de paiement ---

INSERT INTO #MODE_PAIEMENT1
SELECT Noticket, ModePaiement, MontantPaiment
FROM #MODE_PAIEMENT
WHERE NumLigne = 1

INSERT INTO #MODE_PAIEMENT2
SELECT Noticket, ModePaiement, MontantPaiment
FROM #MODE_PAIEMENT
WHERE NumLigne = 2

INSERT INTO #MODE_PAIEMENT3
SELECT Noticket, ModePaiement, MontantPaiment
FROM #MODE_PAIEMENT
WHERE NumLigne = 3

------------------------------------------------------------------
                    --- SELECT FINAL --- 
------------------------------------------------------------------

SELECT 
    F.Noticket                          AS 'Numéro Facture',
    F.Date_Facture                      AS 'Date Facture',
    F.DateVente                         AS 'Date Vente',
    F.IdMag                             AS 'N° Magasin',
    F.Magasin                           AS 'Nom Magasin',
    ISNULL(F.Civilite,'')               AS 'Civilité',
    ISNULL(F.Nom,'')                    AS 'Nom', 
    ISNULL(F.Prenom,'')                 AS 'Prénom',
    ISNULL(F.Cpos,'')                   AS 'Code Postal',
    ISNULL(F.Ville,'')                  AS 'Ville',
    ISNULL(F.Adr1,'')                   AS 'Adresse 1',
    ISNULL(F.Adr2,'')                   AS 'Adresse 2',
    ISNULL(F.Adr3,'')                   AS 'Adresse 3',
    ISNULL(F.Adr4,'')                   AS 'Adresse 4',
    ISNULL(F.EmailCli,'')               AS 'E-Mail',
    ISNULL(F.NumSIRET,'')               AS 'N° SIRET',
    ISNULL(F.NumTVA,'')                 AS 'N° TVA',

    CASE WHEN F.NumTVA = F.ValeurTVA 
        THEN 'OK' 
        ELSE F.ValeurTVA 
        END                             AS 'N° TVA Renseigné',
    CASE WHEN F.ChampTVA = 'NumTVA' 
        THEN 'OK' 
        ELSE F.ChampTVA 
        END                             AS 'Champ TVA Renseigné',

    T21.TVA21                           AS 'TVA 21%',
    T6.TVA6                             AS 'TVA 6%',
    F.TotalTTC                          AS 'Total TTC',

    ISNULL(P1.ModePaiement,'')          AS 'Mode de Paiment 01',
    ISNULL(P1.MontantPaiment,0)         AS 'Montant Paiement 01',
    ISNULL(P2.ModePaiement,'')          AS 'Mode de Paiement 02',
    ISNULL(P2.MontantPaiment,0)         AS 'Montant Paiement 02',
    ISNULL(P3.ModePaiement,'')          AS 'Mode de Paiement 03',
    ISNULL(P3.MontantPaiment,0)         AS 'Montant Paiement 03'

FROM #TEMP_TVA_FACT F

INNER JOIN #TVA21 T21
    ON T21.NoTicket = F.Noticket

INNER JOIN #TVA6 T6 
    ON T6.NoTicket = F.Noticket

LEFT JOIN #MODE_PAIEMENT1 P1
    ON P1.Noticket = F.NoTicket

LEFT JOIN #MODE_PAIEMENT2 P2
    ON P2.Noticket = F.NoTicket

LEFT JOIN #MODE_PAIEMENT3 P3
    ON P3.Noticket = F.NoTicket

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
DROP TABLE #MODE_PAIEMENT
DROP TABLE #MODE_PAIEMENT1
DROP TABLE #MODE_PAIEMENT2
DROP TABLE #MODE_PAIEMENT3