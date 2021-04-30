{-# language DataKinds #-}
{-# language FlexibleContexts #-}
{-# language GADTs #-}
{-# language LambdaCase #-}
{-# language MultiParamTypeClasses #-}
{-# language RankNTypes #-}
{-# language StandaloneKindSignatures #-}
{-# language TypeFamilies #-}
{-# language UndecidableInstances #-}

module Rel8.Schema.Field
  ( Field
  , HEither, HList, HMaybe, HNonEmpty, HThese
  , AField(..)
  , AHEither(..), AHList(..), AHMaybe(..), AHNonEmpty(..), AHThese(..)
  )
where

-- base
import Control.Applicative ( liftA2 )
import Data.Bifunctor ( Bifunctor, bimap )
import Data.Kind ( Type )
import Data.List.NonEmpty ( NonEmpty )
import Prelude

-- rel8
import Rel8.Aggregate ( Aggregate, Col(..) )
import Rel8.Expr ( Expr, Col(..) )
import Rel8.Kind.Context ( SContext(..), Reifiable( contextSing ) )
import Rel8.Kind.Necessity
  ( Necessity( Required, Optional )
  , SNecessity( SRequired, SOptional )
  , KnownNecessity, necessitySing
  )
import Rel8.Schema.HTable.Either ( HEitherTable )
import Rel8.Schema.HTable.List ( HListTable )
import Rel8.Schema.HTable.Maybe ( HMaybeTable )
import Rel8.Schema.HTable.NonEmpty ( HNonEmptyTable )
import Rel8.Schema.HTable.These ( HTheseTable )
import Rel8.Schema.HTable.Identity ( HIdentity( HIdentity ) )
import Rel8.Schema.Insert ( Insert, Col(..) )
import qualified Rel8.Schema.Kind as K
import Rel8.Schema.Name ( Name(..), Col(..) )
import Rel8.Schema.Null ( Sql )
import Rel8.Schema.Reify ( Reify, Col(..), hreify, hunreify )
import Rel8.Schema.Result ( Col( Result ), Result )
import Rel8.Schema.Spec ( Spec( Spec ) )
import Rel8.Table
  ( Table, Columns, Congruent, Context, fromColumns, toColumns
  , Unreify, reify, unreify
  )
import Rel8.Table.Either ( EitherTable )
import Rel8.Table.List ( ListTable( ListTable ) )
import Rel8.Table.Maybe ( MaybeTable )
import Rel8.Table.NonEmpty ( NonEmptyTable( NonEmptyTable ) )
import Rel8.Table.Recontextualize ( Recontextualize )
import Rel8.Table.These ( TheseTable )
import Rel8.Table.Unreify ( Unreifiable )
import Rel8.Type ( DBType )

-- these
import Data.These ( These )


type Field :: K.Context -> Necessity -> Type -> Type
type family Field context necessity a where
  Field (Reify context) necessity  a = AField context necessity a
  Field Aggregate       _necessity a = Aggregate (Expr a)
  Field Expr            _necessity a = Expr a
  Field Insert          'Required  a = Expr a
  Field Insert          'Optional  a = Maybe (Expr a)
  Field Name            _necessity a = Name a
  Field Result          _necessity a = a


type HEither :: K.Context -> Type -> Type -> Type
type family HEither context where
  HEither (Reify context) = AHEither context
  HEither Aggregate = EitherTable
  HEither Expr = EitherTable
  HEither Insert = EitherTable
  HEither Name = EitherTable
  HEither Result = Either


type HList :: K.Context -> Type -> Type
type family HList context where
  HList (Reify context) = AHList context
  HList Aggregate = ListTable
  HList Expr = ListTable
  HList Insert = ListTable
  HList Name = ListTable
  HList Result = []


type HMaybe :: K.Context -> Type -> Type
type family HMaybe context where
  HMaybe (Reify context) = AHMaybe context
  HMaybe Aggregate = MaybeTable
  HMaybe Expr = MaybeTable
  HMaybe Insert = MaybeTable
  HMaybe Name = MaybeTable
  HMaybe Result = Maybe


type HNonEmpty :: K.Context -> Type -> Type
type family HNonEmpty context where
  HNonEmpty (Reify context) = AHNonEmpty context
  HNonEmpty Aggregate = NonEmptyTable
  HNonEmpty Expr = NonEmptyTable
  HNonEmpty Insert = NonEmptyTable
  HNonEmpty Name = NonEmptyTable
  HNonEmpty Result = NonEmpty


type HThese :: K.Context -> Type -> Type -> Type
type family HThese context where
  HThese (Reify context) = AHThese context
  HThese Aggregate = TheseTable
  HThese Expr = TheseTable
  HThese Insert = TheseTable
  HThese Name = TheseTable
  HThese Result = These


type AField :: K.Context -> Necessity -> Type -> Type
newtype AField context necessity a = AField (Field context necessity a)


instance (Reifiable context, KnownNecessity necessity, Sql DBType a) =>
  Table (Reify context) (AField context necessity a)
 where
  type Context (AField context necessity a) = Reify context
  type Columns (AField context necessity a) = HIdentity ('Spec '[""] necessity a)
  type Unreify (AField context necessity a) = Field context necessity a

  fromColumns (HIdentity (Reify a)) = sfromColumn contextSing a
  toColumns = HIdentity . Reify . stoColumn contextSing necessitySing
  reify _ = AField
  unreify _ (AField a) = a


instance
  ( Reifiable context, Reifiable context'
  , KnownNecessity necessity, Sql DBType a
  ) =>
  Recontextualize
    (Reify context)
    (Reify context')
    (AField context necessity a)
    (AField context' necessity a)


type AHEither :: K.Context -> Type -> Type -> Type
newtype AHEither context a b = AHEither (HEither context a b)


instance Reifiable context => Bifunctor (AHEither context) where
  bimap = sbimapEither contextSing


instance Reifiable context => Functor (AHEither context a) where
  fmap = bimap id


instance (Reifiable context, Table (Reify context) a, Table (Reify context) b)
  => Table (Reify context) (AHEither context a b)
 where
  type Context (AHEither context a b) = Reify context
  type Columns (AHEither context a b) = HEitherTable (Columns a) (Columns b)
  type Unreify (AHEither context a b) = HEither context (Unreify a) (Unreify b)

  fromColumns = sfromColumnsEither contextSing
  toColumns = stoColumnsEither contextSing
  reify proof = liftA2 bimap reify reify proof . AHEither
  unreify proof = (\(AHEither a) -> a) . liftA2 bimap unreify unreify proof


instance
  ( Reifiable context, Reifiable context'
  , Recontextualize (Reify context) (Reify context') a a'
  , Recontextualize (Reify context) (Reify context') b b'
  ) =>
  Recontextualize
    (Reify context)
    (Reify context')
    (AHEither context a b)
    (AHEither context' a' b')


type AHList :: K.Context -> Type -> Type
newtype AHList context a = AHList (HList context a)


instance
  ( Reifiable context
  , Table (Reify context) a
  , Unreifiable (Reify context) a
  )
  => Table (Reify context) (AHList context a)
 where
  type Context (AHList context a) = Reify context
  type Columns (AHList context a) = HListTable (Columns a)
  type Unreify (AHList context a) = HList context (Unreify a)

  fromColumns = sfromColumnsList contextSing
  toColumns = stoColumnsList contextSing
  reify proof =
    smapList contextSing (reify proof) hreify .
    AHList
  unreify proof =
    (\(AHList a) -> a) .
    smapList contextSing (unreify proof) hunreify


instance
  ( Reifiable context, Reifiable context'
  , Unreifiable (Reify context) a, Unreifiable (Reify context') a'
  , Recontextualize (Reify context) (Reify context') a a'
  ) =>
  Recontextualize
    (Reify context)
    (Reify context')
    (AHList context a)
    (AHList context' a')


type AHMaybe :: K.Context -> Type -> Type
newtype AHMaybe context a = AHMaybe (HMaybe context a)


instance Reifiable context => Functor (AHMaybe context) where
  fmap = smapMaybe contextSing


instance (Reifiable context, Table (Reify context) a) =>
  Table (Reify context) (AHMaybe context a)
 where
  type Context (AHMaybe context a) = Reify context
  type Columns (AHMaybe context a) = HMaybeTable (Columns a)
  type Unreify (AHMaybe context a) = HMaybe context (Unreify a)

  fromColumns = sfromColumnsMaybe contextSing
  toColumns = stoColumnsMaybe contextSing
  reify proof = fmap fmap reify proof . AHMaybe
  unreify proof = (\(AHMaybe a) -> a) . fmap fmap unreify proof


instance
  ( Reifiable context, Reifiable context'
  , Recontextualize (Reify context) (Reify context') a a'
  ) =>
  Recontextualize
    (Reify context)
    (Reify context')
    (AHMaybe context a)
    (AHMaybe context' a')


type AHNonEmpty :: K.Context -> Type -> Type
newtype AHNonEmpty context a = AHNonEmpty (HNonEmpty context a)


instance
  ( Reifiable context
  , Table (Reify context) a
  , Unreifiable (Reify context) a
  )
  => Table (Reify context) (AHNonEmpty context a)
 where
  type Context (AHNonEmpty context a) = Reify context
  type Columns (AHNonEmpty context a) = HNonEmptyTable (Columns a)
  type Unreify (AHNonEmpty context a) = HNonEmpty context (Unreify a)

  fromColumns = sfromColumnsNonEmpty contextSing
  toColumns = stoColumnsNonEmpty contextSing
  reify proof =
    smapNonEmpty contextSing (reify proof) hreify .
    AHNonEmpty
  unreify proof =
    (\(AHNonEmpty a) -> a) .
    smapNonEmpty contextSing (unreify proof) hunreify


instance
  ( Reifiable context, Reifiable context'
  , Unreifiable (Reify context) a, Unreifiable (Reify context') a'
  , Recontextualize (Reify context) (Reify context') a a'
  ) =>
  Recontextualize
    (Reify context)
    (Reify context')
    (AHNonEmpty context a)
    (AHNonEmpty context' a')


type AHThese :: K.Context -> Type -> Type -> Type
newtype AHThese context a b = AHThese (HThese context a b)


instance Reifiable context => Bifunctor (AHThese context) where
  bimap = sbimapThese contextSing


instance Reifiable context => Functor (AHThese context a) where
  fmap = bimap id


instance (Reifiable context, Table (Reify context) a, Table (Reify context) b)
  => Table (Reify context) (AHThese context a b)
 where
  type Context (AHThese context a b) = Reify context
  type Columns (AHThese context a b) = HTheseTable (Columns a) (Columns b)
  type Unreify (AHThese context a b) = HThese context (Unreify a) (Unreify b)

  fromColumns = sfromColumnsThese contextSing
  toColumns = stoColumnsThese contextSing
  reify proof = liftA2 bimap reify reify proof . AHThese
  unreify proof = (\(AHThese a) -> a) . liftA2 bimap unreify unreify proof


instance
  ( Reifiable context, Reifiable context'
  , Recontextualize (Reify context) (Reify context') a a'
  , Recontextualize (Reify context) (Reify context') b b'
  ) =>
  Recontextualize
    (Reify context)
    (Reify context')
    (AHThese context a b)
    (AHThese context' a' b')


sfromColumn :: ()
  => SContext context
  -> Col context ('Spec labels necessity a)
  -> AField context necessity a
sfromColumn = \case
  SAggregate -> \(Aggregation a) -> AField a
  SExpr -> \(DB a) -> AField a
  SResult -> \(Result a) -> AField a
  SInsert -> \case
    RequiredInsert a -> AField a
    OptionalInsert a -> AField a
  SName -> \(NameCol a) -> AField (Name a)
  SReify context -> \(Reify a) -> AField (sfromColumn context a)


stoColumn :: ()
  => SContext context
  -> SNecessity necessity
  -> AField context necessity a
  -> Col context ('Spec labels necessity a)
stoColumn = \case
  SAggregate -> \_ (AField a) -> Aggregation a
  SExpr -> \_ (AField a) -> DB a
  SResult -> \_ (AField a) -> Result a
  SInsert -> \case
    SRequired -> \(AField a) -> RequiredInsert a
    SOptional -> \(AField a) -> OptionalInsert a
  SName -> \_ (AField (Name a)) -> NameCol a
  SReify context ->
    \necessity (AField a) -> Reify (stoColumn context necessity a)


sbimapEither :: ()
  => SContext context
  -> (a -> c)
  -> (b -> d)
  -> AHEither context a b
  -> AHEither context c d
sbimapEither = \case
  SAggregate -> \f g (AHEither a) -> AHEither (bimap f g a)
  SExpr -> \f g (AHEither a) -> AHEither (bimap f g a)
  SResult -> \f g (AHEither a) -> AHEither (bimap f g a)
  SInsert -> \f g (AHEither a) -> AHEither (bimap f g a)
  SName -> \f g (AHEither a) -> AHEither (bimap f g a)
  SReify context -> \f g (AHEither a) -> AHEither (sbimapEither context f g a)


sfromColumnsEither :: (Table (Reify context) a, Table (Reify context) b)
  => SContext context
  -> HEitherTable (Columns a) (Columns b) (Col (Reify context))
  -> AHEither context a b
sfromColumnsEither = \case
  SAggregate ->
    AHEither .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SExpr ->
    AHEither .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SResult ->
    AHEither .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SInsert ->
    AHEither .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SName ->
    AHEither .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SReify context ->
    AHEither .
    sbimapEither context (fromColumns . hreify) (fromColumns . hreify) .
    sfromColumnsEither context .
    hunreify


stoColumnsEither :: (Table (Reify context) a, Table (Reify context) b)
  => SContext context
  -> AHEither context a b
  -> HEitherTable (Columns a) (Columns b) (Col (Reify context))
stoColumnsEither = \case
  SAggregate ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHEither a) -> a)
  SExpr ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHEither a) -> a)
  SResult ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHEither a) -> a)
  SInsert ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHEither a) -> a)
  SName ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHEither a) -> a)
  SReify context ->
    hreify .
    stoColumnsEither context .
    sbimapEither context (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHEither a) -> a)


smapList :: Congruent a b
  => SContext context
  -> (a -> b)
  -> (HListTable (Columns a) (Col (Context a)) -> HListTable (Columns b) (Col (Context b)))
  -> AHList context a
  -> AHList context b
smapList = \case
  SAggregate -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SExpr -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SResult -> \f _ (AHList as) -> AHList (fmap f as)
  SInsert -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SName -> \_ f (AHList (ListTable a)) -> AHList (ListTable (f a))
  SReify context -> \f g (AHList as) -> AHList (smapList context f g as)


sfromColumnsList :: Table (Reify context) a
  => SContext context
  -> HListTable (Columns a) (Col (Reify context))
  -> AHList context a
sfromColumnsList = \case
  SAggregate -> AHList . ListTable
  SExpr -> AHList . ListTable
  SResult -> AHList . fmap (fromColumns . hreify) . fromColumns . hunreify
  SInsert -> AHList . ListTable
  SName -> AHList . ListTable
  SReify context ->
    AHList .
    smapList context (fromColumns . hreify) hreify .
    sfromColumnsList context .
    hunreify


stoColumnsList :: Table (Reify context) a
  => SContext context
  -> AHList context a
  -> HListTable (Columns a) (Col (Reify context))
stoColumnsList = \case
  SAggregate -> \(AHList (ListTable a)) -> a
  SExpr -> \(AHList (ListTable a)) -> a
  SResult ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHList a) -> a)
  SInsert -> \(AHList (ListTable a)) -> a
  SName -> \(AHList (ListTable a)) -> a
  SReify context ->
    hreify .
    stoColumnsList context .
    smapList context (hunreify . toColumns) hunreify .
    (\(AHList a) -> a)


smapMaybe :: ()
  => SContext context
  -> (a -> b)
  -> AHMaybe context a
  -> AHMaybe context b
smapMaybe = \case
  SAggregate -> \f (AHMaybe a) -> AHMaybe (fmap f a)
  SExpr -> \f (AHMaybe a) -> AHMaybe (fmap f a)
  SResult -> \f (AHMaybe a) -> AHMaybe (fmap f a)
  SInsert -> \f (AHMaybe a) -> AHMaybe (fmap f a)
  SName -> \f (AHMaybe a) -> AHMaybe (fmap f a)
  SReify context -> \f (AHMaybe a) -> AHMaybe (smapMaybe context f a)


sfromColumnsMaybe :: Table (Reify context) a
  => SContext context
  -> HMaybeTable (Columns a) (Col (Reify context))
  -> AHMaybe context a
sfromColumnsMaybe = \case
  SAggregate -> AHMaybe . fmap (fromColumns . hreify) . fromColumns . hunreify
  SExpr -> AHMaybe . fmap (fromColumns . hreify) . fromColumns . hunreify
  SResult -> AHMaybe . fmap (fromColumns . hreify) . fromColumns . hunreify
  SInsert -> AHMaybe . fmap (fromColumns . hreify) . fromColumns . hunreify
  SName -> AHMaybe . fmap (fromColumns . hreify) . fromColumns . hunreify
  SReify context ->
    AHMaybe .
    smapMaybe context (fromColumns . hreify) .
    sfromColumnsMaybe context .
    hunreify


stoColumnsMaybe :: Table (Reify context) a
  => SContext context
  -> AHMaybe context a
  -> HMaybeTable (Columns a) (Col (Reify context))
stoColumnsMaybe = \case
  SAggregate ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHMaybe a) -> a)
  SExpr ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHMaybe a) -> a)
  SResult ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHMaybe a) -> a)
  SInsert ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHMaybe a) -> a)
  SName ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHMaybe a) -> a)
  SReify context ->
    hreify .
    stoColumnsMaybe context .
    smapMaybe context (hunreify . toColumns) .
    (\(AHMaybe a) -> a)


smapNonEmpty :: Congruent a b
  => SContext context
  -> (a -> b)
  -> (HNonEmptyTable (Columns a) (Col (Context a)) -> HNonEmptyTable (Columns b) (Col (Context b)))
  -> AHNonEmpty context a
  -> AHNonEmpty context b
smapNonEmpty = \case
  SAggregate -> \_ f (AHNonEmpty (NonEmptyTable a)) -> AHNonEmpty (NonEmptyTable (f a))
  SExpr -> \_ f (AHNonEmpty (NonEmptyTable a)) -> AHNonEmpty (NonEmptyTable (f a))
  SResult -> \f _ (AHNonEmpty as) -> AHNonEmpty (fmap f as)
  SInsert -> \_ f (AHNonEmpty (NonEmptyTable a)) -> AHNonEmpty (NonEmptyTable (f a))
  SName -> \_ f (AHNonEmpty (NonEmptyTable a)) -> AHNonEmpty (NonEmptyTable (f a))
  SReify context -> \f g (AHNonEmpty as) -> AHNonEmpty (smapNonEmpty context f g as)


sfromColumnsNonEmpty :: Table (Reify context) a
  => SContext context
  -> HNonEmptyTable (Columns a) (Col (Reify context))
  -> AHNonEmpty context a
sfromColumnsNonEmpty = \case
  SAggregate -> AHNonEmpty . NonEmptyTable
  SExpr -> AHNonEmpty . NonEmptyTable
  SResult ->
    AHNonEmpty . fmap (fromColumns . hreify) . fromColumns . hunreify
  SInsert -> AHNonEmpty . NonEmptyTable
  SName -> AHNonEmpty . NonEmptyTable
  SReify context ->
    AHNonEmpty .
    smapNonEmpty context (fromColumns . hreify) hreify .
    sfromColumnsNonEmpty context .
    hunreify


stoColumnsNonEmpty :: Table (Reify context) a
  => SContext context
  -> AHNonEmpty context a
  -> HNonEmptyTable (Columns a) (Col (Reify context))
stoColumnsNonEmpty = \case
  SAggregate -> \(AHNonEmpty (NonEmptyTable a)) -> a
  SExpr -> \(AHNonEmpty (NonEmptyTable a)) -> a
  SResult ->
    hreify . toColumns . fmap (hunreify . toColumns) . (\(AHNonEmpty a) -> a)
  SInsert -> \(AHNonEmpty (NonEmptyTable a)) -> a
  SName -> \(AHNonEmpty (NonEmptyTable a)) -> a
  SReify context ->
    hreify .
    stoColumnsNonEmpty context .
    smapNonEmpty context (hunreify . toColumns) hunreify .
    (\(AHNonEmpty a) -> a)


sbimapThese :: ()
  => SContext context
  -> (a -> c)
  -> (b -> d)
  -> AHThese context a b
  -> AHThese context c d
sbimapThese = \case
  SAggregate -> \f g (AHThese a) -> AHThese (bimap f g a)
  SExpr -> \f g (AHThese a) -> AHThese (bimap f g a)
  SResult -> \f g (AHThese a) -> AHThese (bimap f g a)
  SInsert -> \f g (AHThese a) -> AHThese (bimap f g a)
  SName -> \f g (AHThese a) -> AHThese (bimap f g a)
  SReify context -> \f g (AHThese a) -> AHThese (sbimapThese context f g a)


sfromColumnsThese :: (Table (Reify context) a, Table (Reify context) b)
  => SContext context
  -> HTheseTable (Columns a) (Columns b) (Col (Reify context))
  -> AHThese context a b
sfromColumnsThese = \case
  SAggregate ->
    AHThese .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SExpr ->
    AHThese .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SResult ->
    AHThese .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SInsert ->
    AHThese .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SName ->
    AHThese .
    bimap (fromColumns . hreify) (fromColumns . hreify) .
    fromColumns .
    hunreify
  SReify context ->
    AHThese .
    sbimapThese context (fromColumns . hreify) (fromColumns . hreify) .
    sfromColumnsThese context .
    hunreify


stoColumnsThese :: (Table (Reify context) a, Table (Reify context) b)
  => SContext context
  -> AHThese context a b
  -> HTheseTable (Columns a) (Columns b) (Col (Reify context))
stoColumnsThese = \case
  SAggregate ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHThese a) -> a)
  SExpr ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHThese a) -> a)
  SResult ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHThese a) -> a)
  SInsert ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHThese a) -> a)
  SName ->
    hreify .
    toColumns .
    bimap (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHThese a) -> a)
  SReify context ->
    hreify .
    stoColumnsThese context .
    sbimapThese context (hunreify . toColumns) (hunreify . toColumns) .
    (\(AHThese a) -> a)
